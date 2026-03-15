;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; decision-core.lisp — Typed CL decision-core for runtime health gate arbitration
;;;
;;; Pure functional pipeline: evidence → assessment → aggregation → verdict
;;; with deterministic replay support.

(in-package #:orrery/adapter)

;;; ─── Health Assessment Types ───

(deftype health-status ()
  "Probe health classification."
  '(member :healthy :degraded :unhealthy :unknown))

(deftype probe-domain ()
  "Domain categories for probe findings."
  '(member :transport :auth :schema :conformance :runtime :capability))

(deftype gate-verdict ()
  "Final gate arbitration outcome."
  '(member :pass :degraded :fail))

;;; ─── Probe Finding ───

(defstruct (probe-finding
             (:constructor make-probe-finding
                 (&key domain status severity message evidence-ref))
             (:conc-name pf-))
  "One classified finding from a probe or assessment."
  (domain :runtime :type probe-domain)
  (status :unknown :type health-status)
  (severity 0 :type (integer 0 100))
  (message "" :type string)
  (evidence-ref "" :type string))

;;; ─── Severity Thresholds ───

(defstruct (severity-thresholds
             (:constructor make-severity-thresholds
                 (&key (pass-ceiling 20) (degraded-ceiling 60)))
             (:conc-name st-))
  "Configurable thresholds for verdict mapping."
  (pass-ceiling 20 :type (integer 0 100))
  (degraded-ceiling 60 :type (integer 0 100)))

;;; ─── Replay Seed ───

(defstruct (replay-seed
             (:constructor make-replay-seed
                 (&key timestamp version thresholds))
             (:conc-name rseed-))
  "Deterministic seed for replay."
  (timestamp 0 :type (integer 0))
  (version "1.0.0" :type string)
  (thresholds (make-severity-thresholds) :type severity-thresholds))

;;; ─── Decision Record ───

(defstruct (decision-record
             (:constructor make-decision-record
                 (&key verdict aggregate-score max-severity
                       finding-count findings
                       replay-seed reasoning))
             (:conc-name dec-))
  "Complete gate decision with audit trail."
  (verdict :fail :type gate-verdict)
  (aggregate-score 0 :type (integer 0 100))
  (max-severity 0 :type (integer 0 100))
  (finding-count 0 :type (integer 0))
  (findings '() :type list)
  (replay-seed (make-replay-seed) :type replay-seed)
  (reasoning "" :type string))

;;; ─── Pure Assessment Functions ───

(declaim (ftype (function (keyword keyword) health-status) classify-probe-status))
(defun classify-probe-status (evidence-outcome drift-flag)
  "Classify a probe's health status from evidence outcome and drift flag.
   EVIDENCE-OUTCOME: :pass | :fail | :blocked-external | :inconclusive
   DRIFT-FLAG: :clean | :drifted | :unknown"
  (declare (optimize (safety 3)))
  (cond
    ((and (eq evidence-outcome :pass) (eq drift-flag :clean))
     :healthy)
    ((and (eq evidence-outcome :pass) (eq drift-flag :drifted))
     :degraded)
    ((eq evidence-outcome :blocked-external)
     :degraded)
    ((eq evidence-outcome :fail)
     :unhealthy)
    ((eq evidence-outcome :inconclusive)
     :unknown)
    (t :unknown)))

(declaim (ftype (function (health-status probe-domain) (integer 0 100)) status-to-severity))
(defun status-to-severity (status domain)
  "Map health status + domain to numeric severity (0=fine, 100=critical).
   Domain-specific weighting: :auth and :schema failures are more severe."
  (declare (optimize (safety 3)))
  (let ((base (ecase status
                (:healthy 0)
                (:degraded 35)
                (:unhealthy 75)
                (:unknown 50))))
    (min 100
         (ecase domain
           (:auth (min 100 (+ base 15)))
           (:schema (min 100 (+ base 10)))
           (:transport base)
           (:conformance base)
           (:runtime base)
           (:capability (max 0 (- base 5)))))))

(declaim (ftype (function (keyword keyword probe-domain string string) probe-finding)
                assess-probe))
(defun assess-probe (evidence-outcome drift-flag domain message evidence-ref)
  "Assess a single probe result into a typed finding."
  (declare (optimize (safety 3)))
  (let* ((status (classify-probe-status evidence-outcome drift-flag))
         (severity (status-to-severity status domain)))
    (make-probe-finding
     :domain domain
     :status status
     :severity severity
     :message message
     :evidence-ref evidence-ref)))

;;; ─── Aggregation ───

(declaim (ftype (function (list) (values (integer 0 100) (integer 0 100) &optional))
                aggregate-severities))
(defun aggregate-severities (findings)
  "Aggregate severity scores from findings. Returns (VALUES mean max).
   Empty findings → (VALUES 0 0)."
  (declare (optimize (safety 3)))
  (if (null findings)
      (values 0 0)
      (let ((sum 0)
            (max-sev 0)
            (count 0))
        (declare (type (integer 0) sum count)
                 (type (integer 0 100) max-sev))
        (dolist (f findings)
          (let ((s (pf-severity f)))
            (incf sum s)
            (when (> s max-sev) (setf max-sev s))
            (incf count)))
        (values (if (zerop count) 0 (min 100 (floor sum count)))
                max-sev))))

;;; ─── Verdict Engine ───

(declaim (ftype (function ((integer 0 100) (integer 0 100) severity-thresholds)
                          gate-verdict)
                compute-verdict))
(defun compute-verdict (mean-severity max-severity thresholds)
  "Compute gate verdict from aggregate scores and thresholds.
   Any single finding > 80 severity → immediate :fail."
  (declare (optimize (safety 3)))
  (cond
    ;; Hard-fail: any single critical finding
    ((> max-severity 80) :fail)
    ;; Score-based
    ((<= mean-severity (st-pass-ceiling thresholds)) :pass)
    ((<= mean-severity (st-degraded-ceiling thresholds)) :degraded)
    (t :fail)))

;;; ─── Reasoning Generator ───

(declaim (ftype (function (gate-verdict (integer 0 100) (integer 0 100) list)
                          string)
                generate-reasoning))
(defun generate-reasoning (verdict mean-sev max-sev findings)
  "Generate human-readable reasoning string for the decision."
  (declare (optimize (safety 3)))
  (format nil "Verdict: ~A | Mean severity: ~D/100 | Max severity: ~D/100 | ~D findings~@[ | Critical domains: ~{~A~^, ~}~]"
          verdict mean-sev max-sev
          (length findings)
          (let ((critical (remove-if-not
                           (lambda (f) (> (pf-severity f) 60))
                           findings)))
            (when critical
              (remove-duplicates
               (mapcar (lambda (f) (symbol-name (pf-domain f)))
                       critical)
               :test #'string=)))))

;;; ─── Top-Level Decision Pipeline ───

(declaim (ftype (function (list &key (:thresholds severity-thresholds)
                                    (:timestamp (integer 0)))
                          decision-record)
                run-decision-pipeline))
(defun run-decision-pipeline (findings &key
                                         (thresholds (make-severity-thresholds))
                                         (timestamp 0))
  "Run the full decision pipeline on a list of probe-findings.
   Pure function: same inputs → same decision-record."
  (declare (optimize (safety 3)))
  (multiple-value-bind (mean-sev max-sev)
      (aggregate-severities findings)
    (let* ((verdict (compute-verdict mean-sev max-sev thresholds))
           (seed (make-replay-seed
                  :timestamp timestamp
                  :version "1.0.0"
                  :thresholds thresholds))
           (reasoning (generate-reasoning verdict mean-sev max-sev findings)))
      (make-decision-record
       :verdict verdict
       :aggregate-score mean-sev
       :max-severity max-sev
       :finding-count (length findings)
       :findings findings
       :replay-seed seed
       :reasoning reasoning))))

;;; ─── Replay Verification ───

(declaim (ftype (function (decision-record list) (values boolean string &optional))
                verify-replay))
(defun verify-replay (original-record replay-findings)
  "Verify that replaying with the same findings produces the same verdict.
   Returns (VALUES match-p explanation)."
  (declare (optimize (safety 3)))
  (let* ((seed (dec-replay-seed original-record))
         (replayed (run-decision-pipeline
                    replay-findings
                    :thresholds (rseed-thresholds seed)
                    :timestamp (rseed-timestamp seed))))
    (if (and (eq (dec-verdict replayed) (dec-verdict original-record))
             (= (dec-aggregate-score replayed) (dec-aggregate-score original-record))
             (= (dec-max-severity replayed) (dec-max-severity original-record)))
        (values t "Replay matches original decision")
        (values nil
                (format nil "Replay mismatch: original=~A/~D/~D replayed=~A/~D/~D"
                        (dec-verdict original-record)
                        (dec-aggregate-score original-record)
                        (dec-max-severity original-record)
                        (dec-verdict replayed)
                        (dec-aggregate-score replayed)
                        (dec-max-severity replayed))))))
