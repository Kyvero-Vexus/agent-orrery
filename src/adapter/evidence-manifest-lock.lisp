;;; evidence-manifest-lock.lisp — deterministic lock writers for Epic3/Epic4 evidence
(in-package #:orrery/adapter)

(defstruct (evidence-manifest-lock (:conc-name eml-))
  (epic :epic4 :type keyword)
  (command "" :type string)
  (command-fingerprint 0 :type integer)
  (artifact-root "" :type string)
  (scenario-count 0 :type fixnum)
  (pass-p nil :type boolean)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string) (values integer &optional)) command-fingerprint)
 (ftype (function (evidence-manifest-lock) (values string &optional)) evidence-manifest-lock->json)
 (ftype (function (string string string) (values evidence-manifest-lock &optional)) write-epic4-manifest-lock)
 (ftype (function (string string string) (values evidence-manifest-lock &optional)) write-epic3-manifest-lock))

(defun command-fingerprint (command)
  (declare (type string command))
  (sxhash command))

(defun evidence-manifest-lock->json (lock)
  (declare (type evidence-manifest-lock lock))
  (format nil
          "{\"epic\":\"~(~A~)\",\"command\":\"~A\",\"fingerprint\":~D,\"artifact_root\":\"~A\",\"scenario_count\":~D,\"pass\":~A,\"timestamp\":~D}"
          (eml-epic lock) (eml-command lock) (eml-command-fingerprint lock)
          (eml-artifact-root lock) (eml-scenario-count lock)
          (if (eml-pass-p lock) "true" "false") (eml-timestamp lock)))

(defun %write-lock-file (out-path lock)
  (with-open-file (s out-path :direction :output :if-exists :supersede)
    (write-string (evidence-manifest-lock->json lock) s))
  lock)

(defun write-epic4-manifest-lock (artifact-root command out-path)
  (declare (type string artifact-root command out-path))
  (let* ((manifest (compile-playwright-evidence-manifest artifact-root command))
         (report (verify-runner-evidence
                  manifest *default-web-scenarios* *web-required-artifacts*
                  '(:machine-report) *expected-web-command*))
         (lock (make-evidence-manifest-lock
                :epic :epic4
                :command command
                :command-fingerprint (command-fingerprint command)
                :artifact-root artifact-root
                :scenario-count (length *default-web-scenarios*)
                :pass-p (ecr-pass-p report)
                :timestamp (get-universal-time))))
    (%write-lock-file out-path lock)))

(defun write-epic3-manifest-lock (artifact-root command out-path)
  (declare (type string artifact-root command out-path))
  (let* ((manifest (compile-mcp-tui-evidence-manifest artifact-root command))
         (report (verify-runner-evidence
                  manifest *default-tui-scenarios* *tui-required-artifacts*
                  '(:machine-report :asciicast) *expected-tui-command*))
         (lock (make-evidence-manifest-lock
                :epic :epic3
                :command command
                :command-fingerprint (command-fingerprint command)
                :artifact-root artifact-root
                :scenario-count (length *default-tui-scenarios*)
                :pass-p (ecr-pass-p report)
                :timestamp (get-universal-time))))
    (%write-lock-file out-path lock)))
