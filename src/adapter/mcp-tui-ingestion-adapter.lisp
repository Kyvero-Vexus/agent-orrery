;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-ingestion-adapter.lisp — Epic 3 deterministic ingestion adapter
;;; Bead: agent-orrery-24c

(in-package #:orrery/adapter)

(defparameter *mcp-tui-required-artifact-kinds*
  '(:screenshot :transcript :asciicast :machine-report))

(defstruct (mcp-tui-ingestion-scenario (:conc-name mtis-)
            (:constructor make-mcp-tui-ingestion-scenario
                (&key scenario-id pass-p missing-artifact-kinds artifact-count detail)))
  (scenario-id "" :type string)
  (pass-p nil :type boolean)
  (missing-artifact-kinds '() :type list)
  (artifact-count 0 :type (integer 0))
  (detail "" :type string))

(defstruct (mcp-tui-ingestion-result (:conc-name mtir-)
            (:constructor make-mcp-tui-ingestion-result
                (&key pass-p command-match-p runner-match-p command-fingerprint missing-scenarios
                      scenario-results detail timestamp)))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (runner-match-p nil :type boolean)
  (command-fingerprint 0 :type integer)
  (missing-scenarios '() :type list)
  (scenario-results '() :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (list string evidence-artifact-kind) (values boolean &optional))
        %mtui-scenario-has-kind-p)
 (ftype (function (runner-evidence-manifest string) (values mcp-tui-ingestion-scenario &optional))
        %build-ingestion-scenario)
 (ftype (function (string string) (values mcp-tui-ingestion-result &optional))
        evaluate-mcp-tui-ingestion-adapter)
 (ftype (function (mcp-tui-ingestion-result) (values string &optional))
        mcp-tui-ingestion-result->json))

(defun %mtui-scenario-has-kind-p (artifacts scenario-id kind)
  (declare (type list artifacts)
           (type string scenario-id)
           (type evidence-artifact-kind kind)
           (optimize (safety 3)))
  (loop for a in artifacts
        thereis (and (string= (ea-scenario-id a) scenario-id)
                     (eq (ea-artifact-kind a) kind)
                     (ea-present-p a))))

(defun %build-ingestion-scenario (manifest scenario-id)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id)
           (optimize (safety 3)))
  (let* ((artifacts (rem-artifacts manifest))
         (missing nil)
         (count 0))
    (dolist (kind *mcp-tui-required-artifact-kinds*)
      (if (%mtui-scenario-has-kind-p artifacts scenario-id kind)
          (incf count)
          (push kind missing)))
    (setf missing (nreverse missing))
    (make-mcp-tui-ingestion-scenario
     :scenario-id scenario-id
     :pass-p (null missing)
     :missing-artifact-kinds missing
     :artifact-count count
     :detail (if (null missing)
                 "scenario artifacts complete"
                 "scenario artifacts incomplete"))))

(defun evaluate-mcp-tui-ingestion-adapter (artifacts-dir command)
  "Evaluate deterministic T1-T6 evidence ingestion contract for mcp-tui-driver." 
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((manifest (compile-mcp-tui-evidence-manifest artifacts-dir command))
         (runner-match (string= (rem-runner-id manifest) "mcp-tui-driver"))
         (command-match (string= command *mcp-tui-deterministic-command*))
         (missing-scenarios nil)
         (rows nil))
    (dolist (sid *mcp-tui-required-scenarios*)
      (let ((row (%build-ingestion-scenario manifest sid)))
        (unless (mtis-pass-p row)
          (push sid missing-scenarios))
        (push row rows)))
    (setf rows (nreverse rows)
          missing-scenarios (nreverse missing-scenarios))
    (make-mcp-tui-ingestion-result
     :pass-p (and runner-match command-match (null missing-scenarios))
     :command-match-p command-match
     :runner-match-p runner-match
     :command-fingerprint (command-fingerprint command)
     :missing-scenarios missing-scenarios
     :scenario-results rows
     :detail (if (and runner-match command-match (null missing-scenarios))
                 "Epic 3 ingestion adapter passed: deterministic mcp-tui-driver T1-T6 evidence complete."
                 "Epic 3 ingestion adapter failed: require deterministic mcp-tui-driver command and complete T1-T6 artifacts.")
     :timestamp (get-universal-time))))

(defun %json-escape-mtir (s)
  (declare (type string s) (optimize (safety 3)))
  (with-output-to-string (out)
    (loop for ch across s do
      (case ch
        (#\\ (write-string "\\\\" out))
        (#\" (write-string "\\\"" out))
        (#\Newline (write-string "\\n" out))
        (t (write-char ch out))))))

(defun %kind->json-string (k)
  (declare (type symbol k) (optimize (safety 3)))
  (format nil "\"~(~A~)\"" k))

(defun mcp-tui-ingestion-result->json (result)
  (declare (type mcp-tui-ingestion-result result)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (format s "{\"pass\":~A,\"runner_match\":~A,\"command_match\":~A,\"command_hash\":~D,\"required_runner\":\"mcp-tui-driver\",\"deterministic_command\":\"~A\",\"missing_scenarios\":["
            (if (mtir-pass-p result) "true" "false")
            (if (mtir-runner-match-p result) "true" "false")
            (if (mtir-command-match-p result) "true" "false")
            (mtir-command-fingerprint result)
            (%json-escape-mtir *mcp-tui-deterministic-command*))
    (loop for sid in (mtir-missing-scenarios result)
          for i from 0 do
            (when (> i 0) (write-char #\, s))
            (format s "\"~A\"" sid))
    (write-string "],\"scenario_results\":[" s)
    (loop for row in (mtir-scenario-results result)
          for i from 0 do
            (when (> i 0) (write-char #\, s))
            (format s "{\"scenario_id\":\"~A\",\"pass\":~A,\"artifact_count\":~D,\"missing_artifact_kinds\":["
                    (mtis-scenario-id row)
                    (if (mtis-pass-p row) "true" "false")
                    (mtis-artifact-count row))
            (loop for k in (mtis-missing-artifact-kinds row)
                  for j from 0 do
                    (when (> j 0) (write-char #\, s))
                    (write-string (%kind->json-string k) s))
            (format s "],\"detail\":\"~A\"}" (%json-escape-mtir (mtis-detail row))))
    (format s "],\"detail\":\"~A\",\"timestamp\":~D}"
            (%json-escape-mtir (mtir-detail result))
            (mtir-timestamp result))))
