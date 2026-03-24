;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-drift-classifier.lisp — T1-T6 command-hash drift classifier for Epic 3
;;; Bead: agent-orrery-l7ni

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype tui-drift-class ()
  '(member :no-drift :command-mismatch :lineage-unknown :hash-unstable))

(defparameter *tui-drift-class-order*
  '(:no-drift :command-mismatch :lineage-unknown :hash-unstable))

(defstruct (tui-drift-hint (:conc-name tdh-))
  (scenario-id "" :type string)
  (drift-class :no-drift :type tui-drift-class)
  (expected-hash 0 :type integer)
  (actual-hash 0 :type integer)
  (remediation "" :type string))

(defstruct (tui-drift-classification (:conc-name tdc-))
  (pass-p nil :type boolean)
  (drift-classes nil :type list)         ; list of tui-drift-hint
  (drift-count 0 :type integer)
  (stable-count 0 :type integer)
  (remediation-hints nil :type list)     ; list of remediation strings
  (command-hash 0 :type integer)
  (expected-hash 0 :type integer)
  (detail "" :type string)
  (timestamp 0 :type integer))

;;; ── Declarations ─────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string integer integer) (values tui-drift-hint &optional))
        classify-tui-scenario-drift)
 (ftype (function (mcp-tui-scorecard-result) (values tui-drift-classification &optional))
        classify-tui-command-hash-drift)
 (ftype (function (tui-drift-classification) (values string &optional))
        tui-drift-classification->json))

;;; ── Drift classification ─────────────────────────────────────────────────────

(defun %remediation-for-tui-drift (drift-class scenario-id)
  (declare (type tui-drift-class drift-class)
           (type string scenario-id))
  (case drift-class
    (:no-drift "")
    (:command-mismatch
     (format nil "rerun scenario ~A via: scripts/e2e/run-tui-e2e-deterministic.sh --scenario ~A"
             scenario-id scenario-id))
    (:lineage-unknown
     (format nil "verify scenario ~A command lineage in evidence manifest" scenario-id))
    (:hash-unstable
     (format nil "check deterministic seed/transcript capture for scenario ~A" scenario-id))))

(defun classify-tui-scenario-drift (scenario-id expected-hash actual-hash)
  "Classify drift for a single TUI scenario."
  (declare (type string scenario-id)
           (type integer expected-hash actual-hash)
           (optimize (safety 3)))
  (let* ((drift-class (cond
                        ((= expected-hash 0) :lineage-unknown)
                        ((= actual-hash 0) :lineage-unknown)
                        ((= expected-hash actual-hash) :no-drift)
                        (t :command-mismatch)))
         (remediation (%remediation-for-tui-drift drift-class scenario-id)))
    (make-tui-drift-hint
     :scenario-id scenario-id
     :drift-class drift-class
     :expected-hash expected-hash
     :actual-hash actual-hash
     :remediation remediation)))

(defun classify-tui-command-hash-drift (scorecard)
  "Classify T1-T6 command-hash drift from a scorecard result.
Returns TUI-DRIFT-CLASSIFICATION with per-scenario drift classes and remediation hints."
  (declare (type mcp-tui-scorecard-result scorecard)
           (optimize (safety 3)))
  (let* ((expected-hash (command-fingerprint *mcp-tui-deterministic-command*))
         (actual-hash (mtsr-command-hash scorecard))
         (drift-hints nil)
         (drift-count 0)
         (stable-count 0)
         (remediations nil))
    ;; Classify each T1-T6 scenario
    (dolist (sid *mcp-tui-required-scenarios*)
      (let* ((hint (classify-tui-scenario-drift sid expected-hash actual-hash))
             (drift-class (tdh-drift-class hint)))
        (push hint drift-hints)
        (if (eq drift-class :no-drift)
            (incf stable-count)
            (progn
              (incf drift-count)
              (when (plusp (length (tdh-remediation hint)))
                (push (tdh-remediation hint) remediations))))))
    (setf drift-hints (nreverse drift-hints))
    (setf remediations (nreverse remediations))
    (let* ((pass-p (and (= drift-count 0) (mtsr-pass-p scorecard)))
           (detail (format nil "pass=~A drift=~D stable=~D cmd_hash=~D expected=~D"
                           pass-p drift-count stable-count actual-hash expected-hash)))
      (make-tui-drift-classification
       :pass-p pass-p
       :drift-classes drift-hints
       :drift-count drift-count
       :stable-count stable-count
       :remediation-hints remediations
       :command-hash actual-hash
       :expected-hash expected-hash
       :detail detail
       :timestamp (get-universal-time)))))

;;; ── JSON serializer ───────────────────────────────────────────────────────────

(defun %drift-hint->json (hint)
  (declare (type tui-drift-hint hint))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"drift_class\":\"~(~A~)\",\"expected_hash\":~D,\"actual_hash\":~D,\"remediation\":\"~A\"}"
            (tdh-scenario-id hint)
            (tdh-drift-class hint)
            (tdh-expected-hash hint)
            (tdh-actual-hash hint)
            (%json-escape (tdh-remediation hint)))))

(defun tui-drift-classification->json (classification)
  "Serialize TUI-DRIFT-CLASSIFICATION to JSON with drift_classes and remediation_hints."
  (declare (type tui-drift-classification classification))
  (with-output-to-string (out)
    (format out "{\"pass\":~A,\"drift_count\":~D,\"stable_count\":~D,\"command_hash\":~D,\"expected_hash\":~D,"
            (if (tdc-pass-p classification) "true" "false")
            (tdc-drift-count classification)
            (tdc-stable-count classification)
            (tdc-command-hash classification)
            (tdc-expected-hash classification))
    ;; drift_classes array
    (format out "\"drift_classes\":[")
    (loop for hint in (tdc-drift-classes classification)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (write-string (%drift-hint->json hint) out)))
    (format out "],\"remediation_hints\":[")
    ;; remediation_hints array
    (loop for hint in (tdc-remediation-hints classification)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out "\"~A\"" (%json-escape hint))))
    (format out "],\"detail\":\"~A\",\"timestamp\":~D}"
            (%json-escape (tdc-detail classification))
            (tdc-timestamp classification))))
