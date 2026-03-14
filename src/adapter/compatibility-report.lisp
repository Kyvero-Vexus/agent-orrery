;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; compatibility-report.lisp — Typed compatibility report generator
;;;
;;; Converts adapter contract-harness/probe results into parity-gate
;;; readiness signals consumed by Epics 3-6, with unmet-capability maps
;;; and remediation hints.

(in-package #:orrery/adapter)

;;; ─── Parity Gate Readiness ───

(deftype parity-readiness ()
  '(member :ready :degraded :blocked :unknown))

(defstruct (capability-gap
             (:constructor make-capability-gap
                 (&key capability-name required-by status remediation))
             (:conc-name cg-))
  "An unmet capability needed by a downstream epic."
  (capability-name "" :type string)
  (required-by "" :type string)   ; e.g. "epic-3" "epic-4"
  (status :blocked :type parity-readiness)
  (remediation "" :type string))

(defstruct (parity-gate-signal
             (:constructor make-parity-gate-signal
                 (&key epic-name readiness gaps summary))
             (:conc-name pgs-))
  "Readiness signal for one downstream epic."
  (epic-name "" :type string)
  (readiness :unknown :type parity-readiness)
  (gaps '() :type list)
  (summary "" :type string))

(defstruct (compatibility-report
             (:constructor make-compatibility-report
                 (&key source-verdict signals overall-readiness
                       total-gaps timestamp))
             (:conc-name cr-))
  "Complete compatibility report bridging adapter state to epic gates."
  (source-verdict :gate-skip :type s1-verdict)
  (signals '() :type list)
  (overall-readiness :unknown :type parity-readiness)
  (total-gaps 0 :type fixnum)
  (timestamp 0 :type integer))

;;; ─── Epic Capability Requirements ───

(defparameter *epic-requirements*
  '(("epic-3" . ("health" "sessions-list" "session-history"))
    ("epic-4" . ("health" "sessions-list" "system-status"))
    ("epic-5" . ("health" "sessions-list"))
    ("epic-6" . ("health")))
  "Capability requirements per downstream epic.")

;;; ─── Report Generator ───

(declaim (ftype (function (s1-gate-result) (values compatibility-report &optional))
                generate-compatibility-report)
         (ftype (function (compatibility-report) (values string &optional))
                compatibility-report-to-json))

(defun %check-epic-readiness (s1-result epic-name required-caps)
  "Check readiness for one epic based on S1 gate result."
  (declare (type s1-gate-result s1-result) (type string epic-name) (type list required-caps))
  (let ((gaps '())
        (harness (s1-harness-result s1-result)))
    (if (null harness)
        ;; No harness data → all blocked
        (progn
          (dolist (cap required-caps)
            (push (make-capability-gap
                   :capability-name cap :required-by epic-name
                   :status :blocked :remediation "No harness data available")
                  gaps))
          (make-parity-gate-signal
           :epic-name epic-name :readiness :blocked
           :gaps (nreverse gaps)
           :summary (format nil "~A: blocked (no harness data)" epic-name)))
        ;; Check each required capability against harness checks
        (let ((all-pass t))
          (dolist (cap required-caps)
            (let ((check (find cap (chr-checks harness)
                                :key #'cc-endpoint-name
                                :test (lambda (c name)
                                        (search c name :test #'char-equal)))))
              (cond
                ((null check)
                 (setf all-pass nil)
                 (push (make-capability-gap
                        :capability-name cap :required-by epic-name
                        :status :blocked :remediation "Capability not tested")
                       gaps))
                ((not (eq :pass (cc-verdict check)))
                 (setf all-pass nil)
                 (push (make-capability-gap
                        :capability-name cap :required-by epic-name
                        :status (if (eq :skip (cc-verdict check))
                                    :blocked :degraded)
                        :remediation (cc-message check))
                       gaps)))))
          (make-parity-gate-signal
           :epic-name epic-name
           :readiness (cond (all-pass :ready)
                            ((null gaps) :ready)
                            ((every (lambda (g) (eq :degraded (cg-status g))) gaps) :degraded)
                            (t :blocked))
           :gaps (nreverse gaps)
           :summary (format nil "~A: ~D/~D capabilities met"
                            epic-name
                            (- (length required-caps) (length gaps))
                            (length required-caps)))))))

(defun generate-compatibility-report (s1-result)
  "Generate compatibility report from S1 gate result for all downstream epics."
  (declare (type s1-gate-result s1-result))
  (let ((signals '())
        (total-gaps 0))
    (dolist (req *epic-requirements*)
      (let ((signal (%check-epic-readiness s1-result (car req) (cdr req))))
        (incf total-gaps (length (pgs-gaps signal)))
        (push signal signals)))
    (let* ((ordered (nreverse signals))
           (overall (cond
                      ((every (lambda (s) (eq :ready (pgs-readiness s))) ordered) :ready)
                      ((every (lambda (s) (member (pgs-readiness s) '(:ready :degraded)))
                              ordered) :degraded)
                      (t :blocked))))
      (make-compatibility-report
       :source-verdict (s1-verdict s1-result)
       :signals ordered
       :overall-readiness overall
       :total-gaps total-gaps
       :timestamp (get-universal-time)))))

;;; ─── JSON Serialization ───

(defun compatibility-report-to-json (report)
  "Serialize compatibility report to deterministic JSON."
  (declare (type compatibility-report report))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"source_verdict\":" s)
    (emit-json-string (string-downcase (symbol-name (cr-source-verdict report))) s)
    (write-string ",\"overall_readiness\":" s)
    (emit-json-string (string-downcase (symbol-name (cr-overall-readiness report))) s)
    (write-string ",\"total_gaps\":" s)
    (format s "~D" (cr-total-gaps report))
    (write-string ",\"timestamp\":" s)
    (format s "~D" (cr-timestamp report))
    (write-string ",\"signals\":[" s)
    (let ((first-sig t))
      (dolist (sig (cr-signals report))
        (unless first-sig (write-char #\, s))
        (setf first-sig nil)
        (write-string "{\"epic\":" s)
        (emit-json-string (pgs-epic-name sig) s)
        (write-string ",\"readiness\":" s)
        (emit-json-string (string-downcase (symbol-name (pgs-readiness sig))) s)
        (write-string ",\"summary\":" s)
        (emit-json-string (pgs-summary sig) s)
        (write-string ",\"gaps\":[" s)
        (let ((first-gap t))
          (dolist (g (pgs-gaps sig))
            (unless first-gap (write-char #\, s))
            (setf first-gap nil)
            (write-string "{\"capability\":" s)
            (emit-json-string (cg-capability-name g) s)
            (write-string ",\"status\":" s)
            (emit-json-string (string-downcase (symbol-name (cg-status g))) s)
            (write-string ",\"remediation\":" s)
            (emit-json-string (cg-remediation g) s)
            (write-string "}" s)))
        (write-string "]}" s)))
    (write-string "]}" s)))
