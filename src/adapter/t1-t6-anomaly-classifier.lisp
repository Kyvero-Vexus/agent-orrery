;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-anomaly-classifier.lisp
;;;   Typed CL anomaly classifier for mcp-tui-driver T1-T6 deterministic
;;;   evidence sets. Emits machine-checkable anomaly classes with remediation
;;;   hints for Epic 3 closure gate workflows.
;;;
;;; Bead: agent-orrery-8lum
;;;
;;; Deterministic command: cd e2e-tui && ./run-tui-e2e-t1-t6.sh
;;; Design doc: /home/slime/projects/emacsen-design-docs/agent-orrery/
;;;             epic-3-anomaly-classifier-8lum.md

(in-package #:orrery/adapter)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Type declarations
;;; ─────────────────────────────────────────────────────────────────────────────

(deftype t1-t6-anomaly-class ()
  '(member :missing-scenario
           :command-drift
           :transcript-digest-mismatch
           :artifact-missing
           :artifact-checksum-drift
           :clean))

(deftype t1-t6-anomaly-gate-verdict ()
  '(member :clean :anomalous :rejected))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: t1-t6-anomaly
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (t1-t6-anomaly (:conc-name anom-))
  "Single anomaly record for one T1-T6 evidence field."
  (anomaly-class       :clean :type t1-t6-anomaly-class)
  (scenario-id         :T1    :type symbol)  ; :T1..:T6 or :GLOBAL
  (field               ""     :type string)
  (detail              ""     :type string)
  (remediation-hint    ""     :type string))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: t1-t6-anomaly-report
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (t1-t6-anomaly-report (:conc-name anomrep-))
  "Full anomaly classification report for a T1-T6 evidence set."
  (anomalies           nil  :type list)    ; list of t1-t6-anomaly
  (gate-verdict        :clean :type t1-t6-anomaly-gate-verdict)
  (anomaly-count       0    :type fixnum)
  (timestamp           0    :type integer))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Constants
;;; ─────────────────────────────────────────────────────────────────────────────

(defparameter *t1-t6-canonical-anomaly-command*
  "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
  "Canonical deterministic command for anomaly classification gate.")

(defparameter *t1-t6-required-artifact-kinds-anomaly*
  '("transcript" "screenshot" "asciicast" "report")
  "Required artifact kinds for anomaly-free T1-T6 scenarios.")

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Declaims
;;; ─────────────────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (fixture-checksum-registry) (values t1-t6-anomaly-report &optional))
        classify-registry-anomalies)
 (ftype (function (fixture-checksum-registry fixture-checksum-registry)
                  (values t1-t6-anomaly-report &optional))
        classify-rerun-anomalies)
 (ftype (function (t1-t6-anomaly-report) (values t1-t6-anomaly-gate-verdict &optional))
        evaluate-anomaly-gate)
 (ftype (function (t1-t6-anomaly-report) (values string &optional))
        anomaly-report->json))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Remediation hints
;;; ─────────────────────────────────────────────────────────────────────────────

(defun %remediation-for-anomaly (class field)
  "Return a standard remediation hint string for ANOMALY-CLASS and FIELD."
  (declare (type t1-t6-anomaly-class class)
           (type string field))
  (case class
    (:missing-scenario
     (format nil "Re-run 'cd e2e-tui && ./run-tui-e2e-t1-t6.sh' to generate ~A evidence" field))
    (:command-drift
     "Reset deterministic command to: cd e2e-tui && ./run-tui-e2e-t1-t6.sh")
    (:transcript-digest-mismatch
     (format nil "Rerun T1-T6 suite and compare transcripts for ~A; check for non-deterministic output" field))
    (:artifact-missing
     (format nil "Regenerate missing artifact '~A' by rerunning the T1-T6 suite" field))
    (:artifact-checksum-drift
     (format nil "Artifact '~A' checksum drifted; verify test isolation and rerun" field))
    (:clean "No remediation required")
    (t "Investigate anomaly and rerun T1-T6 suite")))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Single-registry classification
;;; ─────────────────────────────────────────────────────────────────────────────

(defun %classify-entry (entry)
  "Classify a single fixture-checksum-entry, returning list of t1-t6-anomaly."
  (declare (type fixture-checksum-entry entry))
  (let ((sid (fce-scenario-id entry))
        (anomalies '()))
    ;; Missing required artifacts
    (dolist (missing-key (fce-missing-keys entry))
      (push (make-t1-t6-anomaly
             :anomaly-class :artifact-missing
             :scenario-id sid
             :field missing-key
             :detail (format nil "Scenario ~A missing artifact: ~A" sid missing-key)
             :remediation-hint
             (%remediation-for-anomaly :artifact-missing missing-key))
            anomalies))
    ;; Drifted artifacts
    (dolist (drift-key (fce-drift-keys entry))
      (push (make-t1-t6-anomaly
             :anomaly-class :artifact-checksum-drift
             :scenario-id sid
             :field drift-key
             :detail (format nil "Scenario ~A artifact checksum drifted: ~A" sid drift-key)
             :remediation-hint
             (%remediation-for-anomaly :artifact-checksum-drift drift-key))
            anomalies))
    (nreverse anomalies)))

(defun classify-registry-anomalies (registry)
  "Classify all anomalies in REGISTRY by inspecting each scenario entry.
   Emits :missing-scenario anomalies for absent scenarios.
   Returns a t1-t6-anomaly-report."
  (declare (type fixture-checksum-registry registry))
  (let ((anomalies '()))
    ;; Check for missing scenarios
    (dolist (sid *t1-t6-all-scenario-ids*)
      (unless (find sid (fcr-entries registry) :key #'fce-scenario-id)
        (push (make-t1-t6-anomaly
               :anomaly-class :missing-scenario
               :scenario-id sid
               :field (symbol-name sid)
               :detail (format nil "Scenario ~A absent from registry" sid)
               :remediation-hint
               (%remediation-for-anomaly :missing-scenario (symbol-name sid)))
              anomalies)))
    ;; Classify each present entry
    (dolist (entry (fcr-entries registry))
      (setf anomalies (append anomalies (%classify-entry entry))))
    ;; Determine gate verdict
    (let* ((anom-count (length anomalies))
           (has-missing-scenario-p
             (some (lambda (a) (eq (anom-anomaly-class a) :missing-scenario))
                   anomalies))
           (gate-verdict
             (cond
               ((zerop anom-count)          :clean)
               (has-missing-scenario-p      :rejected)
               (t                           :anomalous))))
      (make-t1-t6-anomaly-report
       :anomalies anomalies
       :gate-verdict gate-verdict
       :anomaly-count anom-count
       :timestamp (get-universal-time)))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Cross-rerun classification
;;; ─────────────────────────────────────────────────────────────────────────────

(defun classify-rerun-anomalies (old-registry new-registry)
  "Cross-compare OLD-REGISTRY and NEW-REGISTRY for transcript digest mismatches.
   Detects :transcript-digest-mismatch and :missing-scenario anomalies.
   Fails closed: missing scenarios in new run → :rejected gate verdict."
  (declare (type fixture-checksum-registry old-registry)
           (type fixture-checksum-registry new-registry))
  (let ((anomalies '()))
    (dolist (sid *t1-t6-all-scenario-ids*)
      (let ((old-e (find sid (fcr-entries old-registry) :key #'fce-scenario-id))
            (new-e (find sid (fcr-entries new-registry) :key #'fce-scenario-id)))
        (cond
          ((null new-e)
           (push (make-t1-t6-anomaly
                  :anomaly-class :missing-scenario
                  :scenario-id sid
                  :field (symbol-name sid)
                  :detail (format nil "Scenario ~A absent from new registry" sid)
                  :remediation-hint
                  (%remediation-for-anomaly :missing-scenario (symbol-name sid)))
                 anomalies))
          ((and old-e
                (not (string= (fce-transcript-digest old-e)
                              (fce-transcript-digest new-e))))
           (push (make-t1-t6-anomaly
                  :anomaly-class :transcript-digest-mismatch
                  :scenario-id sid
                  :field "transcript_digest"
                  :detail (format nil "~A transcript digest changed: ~A -> ~A"
                                  sid
                                  (fce-transcript-digest old-e)
                                  (fce-transcript-digest new-e))
                  :remediation-hint
                  (%remediation-for-anomaly :transcript-digest-mismatch
                                          (symbol-name sid)))
                 anomalies)))))
    (let* ((anom-count (length anomalies))
           (has-missing-p
             (some (lambda (a) (eq (anom-anomaly-class a) :missing-scenario))
                   anomalies))
           (gate-verdict
             (cond
               ((zerop anom-count)  :clean)
               (has-missing-p       :rejected)
               (t                   :anomalous))))
      (make-t1-t6-anomaly-report
       :anomalies (nreverse anomalies)
       :gate-verdict gate-verdict
       :anomaly-count anom-count
       :timestamp (get-universal-time)))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Gate evaluation
;;; ─────────────────────────────────────────────────────────────────────────────

(defun evaluate-anomaly-gate (report)
  "Return gate verdict from REPORT.
   :clean — no anomalies
   :anomalous — anomalies present but no missing scenarios
   :rejected — missing scenario(s) detected (fail closed)"
  (declare (type t1-t6-anomaly-report report))
  (anomrep-gate-verdict report))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; JSON serialization
;;; ─────────────────────────────────────────────────────────────────────────────

(defun anom->json (a)
  "Serialize a t1-t6-anomaly to a JSON object string."
  (declare (type t1-t6-anomaly a))
  (format nil
   "{\"anomaly_class\":\"~A\",\"scenario_id\":\"~A\",\"field\":\"~A\",\"detail\":\"~A\",\"remediation\":\"~A\"}"
   (symbol-name (anom-anomaly-class a))
   (symbol-name (anom-scenario-id a))
   (anom-field a)
   (anom-detail a)
   (anom-remediation-hint a)))

(defun anomaly-report->json (report)
  "Serialize a t1-t6-anomaly-report to a machine-checkable JSON string."
  (declare (type t1-t6-anomaly-report report))
  (format nil
   "{\"gate_verdict\":\"~A\",\"anomaly_count\":~A,\"timestamp\":~A,\"anomalies\":[~{~A~^,~}]}"
   (symbol-name (anomrep-gate-verdict report))
   (anomrep-anomaly-count report)
   (anomrep-timestamp report)
   (mapcar #'anom->json (anomrep-anomalies report))))
