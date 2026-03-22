;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-ingestion-adapter.lisp — Epic4 Playwright S1-S6 ingestion adapter
;;; Bead: agent-orrery-9d8

(in-package #:orrery/adapter)

(defstruct (playwright-ingestion-scenario (:conc-name pwis-)
            (:constructor make-playwright-ingestion-scenario
                (&key scenario-id pass-p artifact-count missing-artifact-kinds detail)))
  (scenario-id "" :type string)
  (pass-p nil :type boolean)
  (artifact-count 0 :type (integer 0))
  (missing-artifact-kinds '() :type list)
  (detail "" :type string))

(defstruct (playwright-ingestion-result (:conc-name pwir-)
            (:constructor make-playwright-ingestion-result
                (&key pass-p command-match-p command-fingerprint missing-scenarios
                      scenario-results detail timestamp)))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (command-fingerprint 0 :type integer)
  (missing-scenarios '() :type list)
  (scenario-results '() :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string) (values list &optional)) collect-playwright-s1-s6-rows)
 (ftype (function (string string) (values playwright-ingestion-result &optional))
        evaluate-playwright-ingestion-adapter)
 (ftype (function (playwright-ingestion-result) (values string &optional))
        playwright-ingestion-result->json))

(defun %present-web-artifact-p (root sid kind)
  (declare (type string root sid) (type evidence-artifact-kind kind) (optimize (safety 3)))
  (let ((pat (ecase kind
               (:screenshot (format nil "~A*shot*.png" sid))
               (:trace (format nil "~A*trace*.zip" sid))
               (:machine-report (format nil "~A*report*.json" sid)))))
    (not (null (directory (merge-pathnames pat (pathname root)))))))

(defun collect-playwright-s1-s6-rows (artifacts-root)
  (declare (type string artifacts-root) (optimize (safety 3)))
  (let ((rows nil))
    (dolist (sid *playwright-required-scenarios*)
      (let* ((has-shot (%present-web-artifact-p artifacts-root sid :screenshot))
             (has-trace (%present-web-artifact-p artifacts-root sid :trace))
             (missing nil)
             (count 0))
        (unless has-shot (push :screenshot missing))
        (unless has-trace (push :trace missing))
        (when has-shot (incf count))
        (when has-trace (incf count))
        (push (make-playwright-ingestion-scenario
               :scenario-id sid
               :pass-p (null missing)
               :artifact-count count
               :missing-artifact-kinds (nreverse missing)
               :detail (if missing "scenario artifacts incomplete" "scenario artifacts complete"))
              rows)))
    (nreverse rows)))

(defun evaluate-playwright-ingestion-adapter (artifacts-root command)
  (declare (type string artifacts-root command) (optimize (safety 3)))
  (let* ((rows (collect-playwright-s1-s6-rows artifacts-root))
         (missing (mapcar #'pwis-scenario-id (remove-if #'pwis-pass-p rows)))
         (command-match (string= command *playwright-deterministic-command*))
         (pass (and command-match (null missing))))
    (make-playwright-ingestion-result
     :pass-p pass
     :command-match-p command-match
     :command-fingerprint (command-fingerprint command)
     :missing-scenarios missing
     :scenario-results rows
     :detail (if pass
                 "Epic 4 ingestion adapter passed: deterministic Playwright S1-S6 evidence complete."
                 "Epic 4 ingestion adapter failed: require deterministic Playwright command and complete S1-S6 screenshot+trace artifacts.")
     :timestamp (get-universal-time))))

(defun playwright-ingestion-result->json (result)
  (declare (type playwright-ingestion-result result) (optimize (safety 3)))
  (with-output-to-string (s)
    (format s "{\"pass\":~A,\"command_match\":~A,\"command_hash\":~D,\"required_runner\":\"playwright\",\"deterministic_command\":\"~A\",\"missing_scenarios\":["
            (if (pwir-pass-p result) "true" "false")
            (if (pwir-command-match-p result) "true" "false")
            (pwir-command-fingerprint result)
            *playwright-deterministic-command*)
    (loop for sid in (pwir-missing-scenarios result)
          for i from 0 do
            (when (> i 0) (write-char #\, s))
            (format s "\"~A\"" sid))
    (write-string "],\"scenarios\":[" s)
    (loop for row in (pwir-scenario-results result)
          for i from 0 do
            (when (> i 0) (write-char #\, s))
            (format s "{\"scenario_id\":\"~A\",\"pass\":~A,\"artifact_count\":~D,\"missing_artifact_kinds\":["
                    (pwis-scenario-id row)
                    (if (pwis-pass-p row) "true" "false")
                    (pwis-artifact-count row))
            (loop for k in (pwis-missing-artifact-kinds row)
                  for j from 0 do
                    (when (> j 0) (write-char #\, s))
                    (format s "\"~(~A~)\"" k))
            (format s "],\"detail\":\"~A\"}" (pwis-detail row)))
    (format s "],\"detail\":\"~A\",\"timestamp\":~D}"
            (pwir-detail result)
            (pwir-timestamp result))))
