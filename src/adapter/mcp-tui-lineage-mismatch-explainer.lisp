;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-lineage-mismatch-explainer.lisp — T1-T6 lineage mismatch explainer + remediation matrix
;;; Bead: agent-orrery-amvi

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype tui-lineage-mismatch-class ()
  '(member :no-mismatch :command-drift :digest-mismatch :lineage-incomplete :artifact-missing))

(defparameter *tui-lineage-mismatch-class-order*
  '(:no-mismatch :command-drift :digest-mismatch :lineage-incomplete :artifact-missing))

(defstruct (tui-lineage-remediation-step (:conc-name tlrs-))
  (step-id "" :type string)
  (description "" :type string)
  (command "" :type string))

(defstruct (tui-lineage-mismatch-entry (:conc-name tlme-))
  (scenario-id "" :type string)
  (mismatch-class :no-mismatch :type symbol)  ; Use symbol instead of restricted type
  (expected-command "" :type string)
  (actual-command "" :type string)
  (expected-digest "" :type string)
  (actual-digest "" :type string)
  (remediation-steps nil :type list)
  (detail "" :type string))

(defstruct (tui-lineage-mismatch-report (:conc-name tlmr-))
  (pass-p nil :type boolean)
  (mismatch-count 0 :type integer)
  (clean-count 0 :type integer)
  (mismatch-matrix nil :type list)         ; list of tui-lineage-mismatch-entry
  (by-mismatch-class nil :type list)       ; alist of (class . entries)
  (remediation-matrix nil :type list)      ; consolidated remediation matrix
  (command-hash 0 :type integer)
  (detail "" :type string)
  (timestamp 0 :type integer))

;;; ── Declarations ─────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string t) (values tui-lineage-mismatch-entry &optional))
        build-tui-lineage-mismatch-entry)
 (ftype (function (mcp-tui-scorecard-result) (values tui-lineage-mismatch-report &optional))
        explain-tui-lineage-mismatches)
 (ftype (function (tui-lineage-mismatch-report) (values string &optional))
        tui-lineage-mismatch-report->json))

;;; ── Remediation step builders ────────────────────────────────────────────────

(defun %remediation-step (step-id description command)
  (declare (type string step-id description command))
  (make-tui-lineage-remediation-step
   :step-id step-id
   :description description
   :command command))

(defun %remediation-for-mismatch-class (mismatch-class scenario-id)
  (declare (type string scenario-id))
  (case mismatch-class
    (:no-mismatch nil)
    (:command-drift
     (list (%remediation-step
            "rerun-deterministic"
            "Rerun scenario with deterministic command"
            (format nil "~A --scenario ~A" orrery/adapter:*mcp-tui-deterministic-command* scenario-id))))
    (:digest-mismatch
     (list (%remediation-step
            "verify-digest"
            "Verify artifact digest matches expected"
            (format nil "sha256sum artifacts/tui/~A/*.json" scenario-id))
           (%remediation-step
            "rerun-deterministic"
            "Rerun scenario with deterministic command"
            (format nil "~A --scenario ~A" orrery/adapter:*mcp-tui-deterministic-command* scenario-id))))
    (:lineage-incomplete
     (list (%remediation-step
            "check-manifest"
            "Verify lineage manifest is complete"
            (format nil "cat artifacts/tui/~A/lineage.json" scenario-id))))
    (:artifact-missing
     (list (%remediation-step
            "rerun-deterministic"
            "Rerun scenario to generate missing artifacts"
            (format nil "~A --scenario ~A" orrery/adapter:*mcp-tui-deterministic-command* scenario-id))))))

;;; ── Entry builder ─────────────────────────────────────────────────────────────

(defun build-tui-lineage-mismatch-entry (scenario-id mismatch-class)
  "Build a lineage mismatch entry for a TUI scenario."
  (declare (type string scenario-id))
  (let* ((cmd orrery/adapter:*mcp-tui-deterministic-command*)
         (remediation (%remediation-for-mismatch-class mismatch-class scenario-id))
         (detail (if (eq mismatch-class :no-mismatch)
                     (format nil "scenario ~A: lineage ok" scenario-id)
                     (format nil "scenario ~A: ~A" scenario-id mismatch-class))))
    (make-tui-lineage-mismatch-entry
     :scenario-id scenario-id
     :mismatch-class mismatch-class
     :expected-command cmd
     :actual-command (if (eq mismatch-class :command-drift) "" cmd)
     :expected-digest ""
     :actual-digest ""
     :remediation-steps remediation
     :detail detail)))

;;; ── Explainer ─────────────────────────────────────────────────────────────────

(defun explain-tui-lineage-mismatches (scorecard)
  "Explain T1-T6 lineage mismatches from a scorecard result.
Returns TUI-LINEAGE-MISMATCH-REPORT with remediation matrix."
  (declare (type mcp-tui-scorecard-result scorecard)
           )
  (let* ((cmd orrery/adapter:*mcp-tui-deterministic-command*)
         (expected-hash (command-fingerprint cmd))
         (provided-hash (mtsr-command-hash scorecard))
         (command-drift-p (/= expected-hash provided-hash))
         (entries nil)
         (mismatch-count 0)
         (clean-count 0)
         (mismatch-classes nil))
    ;; Build entry for each T1-T6 scenario
    (dolist (sid orrery/adapter:*mcp-tui-required-scenarios*)
      (let* ((scenario-missing (find sid (mtsr-missing-scenarios scorecard) :test #'string=))
             (mismatch-class (cond
                               (scenario-missing :artifact-missing)
                               (command-drift-p :command-drift)
                               (t :no-mismatch)))
             (entry (build-tui-lineage-mismatch-entry sid mismatch-class)))
        (push entry entries)
        (if (eq mismatch-class :no-mismatch)
            (incf clean-count)
            (progn
              (incf mismatch-count)
              (push entry mismatch-classes)))))
    
    (setf entries (nreverse entries))
    (setf mismatch-classes (nreverse mismatch-classes))
    
    ;; Build by-mismatch-class index and remediation matrix
    (let* ((by-class nil)
           (remediation-matrix nil))
      (dolist (entry entries)
        (let ((class (tlme-mismatch-class entry)))
          (unless (assoc class by-class)
            (push (cons class nil) by-class))
          (push entry (cdr (assoc class by-class)))))
      (setf by-class (nreverse by-class))
      (dolist (entry mismatch-classes)
        (when (tlme-remediation-steps entry)
          (push (cons (tlme-scenario-id entry)
                      (tlme-remediation-steps entry))
                remediation-matrix)))
      (setf remediation-matrix (nreverse remediation-matrix))
      (let* ((pass-p (and (not command-drift-p)
                          (mtsr-pass-p scorecard)
                          (= 0 mismatch-count)))
             (detail (format nil "pass=~A clean=~D mismatch=~D cmd_drift=~A"
                             pass-p clean-count mismatch-count command-drift-p)))
        (make-tui-lineage-mismatch-report
         :pass-p pass-p
         :mismatch-count mismatch-count
         :clean-count clean-count
         :mismatch-matrix entries
         :by-mismatch-class by-class
         :remediation-matrix remediation-matrix
         :command-hash provided-hash
         :detail detail
         :timestamp (get-universal-time))))))

;;; ── JSON serializer ───────────────────────────────────────────────────────────

(defun %remediation-step->json (step)
  (declare (type tui-lineage-remediation-step step))
  (format nil "{\"step_id\":\"~A\",\"description\":\"~A\",\"command\":\"~A\"}"
          (%tlme-json-escape (tlrs-step-id step))
          (%tlme-json-escape (tlrs-description step))
          (%tlme-json-escape (tlrs-command step))))

(defun %tlme-json-escape (input)
  (declare (type string input))
  (with-output-to-string (out)
    (loop for ch across input
          do (case ch
               (#\\ (write-string "\\\\" out))
               (#\" (write-string "\\\"" out))
               (#\Newline (write-string "\\n" out))
               (t (write-char ch out))))))

(defun %mismatch-entry->json (entry)
  (declare (type tui-lineage-mismatch-entry entry))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"mismatch_class\":\"~(~A~)\","
            (%tlme-json-escape (tlme-scenario-id entry))
            (tlme-mismatch-class entry))
    (format out "\"expected_command\":\"~A\",\"actual_command\":\"~A\","
            (%tlme-json-escape (tlme-expected-command entry))
            (%tlme-json-escape (tlme-actual-command entry)))
    (format out "\"expected_digest\":\"~A\",\"actual_digest\":\"~A\","
            (%tlme-json-escape (tlme-expected-digest entry))
            (%tlme-json-escape (tlme-actual-digest entry)))
    (format out "\"remediation_steps\":[")
    (loop for step in (tlme-remediation-steps entry)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (write-string (%remediation-step->json step) out)))
    (format out "],\"detail\":\"~A\"}" (%tlme-json-escape (tlme-detail entry)))))

(defun tui-lineage-mismatch-report->json (report)
  "Serialize TUI-LINEAGE-MISMATCH-REPORT to JSON with remediation_matrix."
  (declare (type tui-lineage-mismatch-report report))
  (with-output-to-string (out)
    (format out "{\"pass\":~A,\"clean_count\":~D,\"mismatch_count\":~D,\"command_hash\":~D,"
            (if (tlmr-pass-p report) "true" "false")
            (tlmr-clean-count report)
            (tlmr-mismatch-count report)
            (tlmr-command-hash report))
    ;; mismatch_matrix array
    (format out "\"mismatch_matrix\":[")
    (loop for entry in (tlmr-mismatch-matrix report)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (write-string (%mismatch-entry->json entry) out)))
    (format out "],\"by_mismatch_class\":{")
    (loop for (class . entries) in (tlmr-by-mismatch-class report)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~(~A~)\":[" class)
               (loop for entry in entries
                     for j from 0
                     do (progn
                          (when (> j 0) (write-string "," out))
                          (write-string (%mismatch-entry->json entry) out)))
               (write-string "]" out)))
    (format out "},\"remediation_matrix\":{")
    (loop for (scenario-id . steps) in (tlmr-remediation-matrix report)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~A\":[" (%tlme-json-escape scenario-id))
               (loop for step in steps
                     for j from 0
                     do (progn
                          (when (> j 0) (write-string "," out))
                          (write-string (%remediation-step->json step) out)))
               (write-string "]" out)))
    (format out "},\"detail\":\"~A\",\"timestamp\":~D}"
            (%tlme-json-escape (tlmr-detail report))
            (tlmr-timestamp report))))
