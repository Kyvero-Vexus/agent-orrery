;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; evidence-gap-explainer.lisp — typed closure-gate evidence-gap explainer
;;; Bead: agent-orrery-fdtj

(in-package #:orrery/adapter)

(defstruct (evidence-gap-explanation (:conc-name ege-))
  (pass-p nil :type boolean)
  (web-pass-p nil :type boolean)
  (tui-pass-p nil :type boolean)
  (blockers '() :type list)
  (remediation-commands '() :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string string string) (values evidence-gap-explanation &optional))
        explain-epic34-evidence-gaps)
 (ftype (function (evidence-gap-explanation) (values string &optional))
        evidence-gap-explanation->json))

(defun %finding->blocker (prefix finding)
  (declare (type string prefix)
           (type evidence-finding finding)
           (optimize (safety 3)))
  (format nil "~A:~A:~A"
          prefix
          (ef-code finding)
          (ef-message finding)))

(defun %report-blockers (prefix report)
  (declare (type string prefix)
           (type evidence-compliance-report report)
           (optimize (safety 3)))
  (let ((blockers '()))
    (dolist (finding (ecr-findings report))
      (push (%finding->blocker prefix finding) blockers))
    (nreverse blockers)))

(defun %framework-remediation-commands (framework web-artifacts-dir tui-artifacts-dir)
  (declare (type keyword framework)
           (type string web-artifacts-dir tui-artifacts-dir)
           (optimize (safety 3)))
  (ecase framework
    (:epic4
     (list
      "cd e2e && bash run-e2e.sh"
      (format nil "sbcl --script ci/check-playwright-evidence-pack-index.lisp -- --artifacts ~A --command 'cd e2e && ./run-e2e.sh'" web-artifacts-dir)
      (format nil "sbcl --script ci/check-epic34-closure-gate.lisp -- --web-artifacts ~A --web-command 'cd e2e && ./run-e2e.sh' --tui-artifacts ~A --tui-command 'cd e2e-tui && ./run-tui-e2e-t1-t6.sh'"
              web-artifacts-dir tui-artifacts-dir)))
    (:epic3
     (list
      "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
      (format nil "sbcl --script ci/check-mcp-tui-artifact-notarizer.lisp -- --artifacts ~A --command 'cd e2e-tui && ./run-tui-e2e-t1-t6.sh'" tui-artifacts-dir)
      (format nil "sbcl --script ci/check-epic34-closure-gate.lisp -- --web-artifacts ~A --web-command 'cd e2e && ./run-e2e.sh' --tui-artifacts ~A --tui-command 'cd e2e-tui && ./run-tui-e2e-t1-t6.sh'"
              web-artifacts-dir tui-artifacts-dir)))))

(defun explain-epic34-evidence-gaps (web-artifacts-dir web-command tui-artifacts-dir tui-command)
  "Explain machine-checkable closure blockers and deterministic remediation commands."
  (declare (type string web-artifacts-dir web-command tui-artifacts-dir tui-command)
           (optimize (safety 3)))
  (let* ((web-manifest (compile-playwright-evidence-manifest web-artifacts-dir web-command))
         (web-report (verify-runner-evidence
                      web-manifest
                      *default-web-scenarios*
                      *web-required-artifacts*
                      '(:machine-report)
                      *expected-web-command*))
         (tui-manifest (compile-mcp-tui-evidence-manifest tui-artifacts-dir tui-command))
         (tui-report (verify-runner-evidence
                      tui-manifest
                      *default-tui-scenarios*
                      *tui-required-artifacts*
                      '(:machine-report :asciicast)
                      *expected-tui-command*))
         (web-pass (ecr-pass-p web-report))
         (tui-pass (ecr-pass-p tui-report))
         (pass (and web-pass tui-pass))
         (blockers (append (%report-blockers "epic4" web-report)
                           (%report-blockers "epic3" tui-report)))
         (commands (append (unless web-pass
                             (%framework-remediation-commands :epic4 web-artifacts-dir tui-artifacts-dir))
                           (unless tui-pass
                             (%framework-remediation-commands :epic3 web-artifacts-dir tui-artifacts-dir)))))
    (make-evidence-gap-explanation
     :pass-p pass
     :web-pass-p web-pass
     :tui-pass-p tui-pass
     :blockers blockers
     :remediation-commands commands
     :detail (format nil "epic4=~A epic3=~A blockers=~D" web-pass tui-pass (length blockers))
     :timestamp (get-universal-time))))

(defun evidence-gap-explanation->json (result)
  (declare (type evidence-gap-explanation result)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"pass\":" s)
    (write-string (if (ege-pass-p result) "true" "false") s)
    (write-string ",\"epic4_pass\":" s)
    (write-string (if (ege-web-pass-p result) "true" "false") s)
    (write-string ",\"epic3_pass\":" s)
    (write-string (if (ege-tui-pass-p result) "true" "false") s)
    (write-string ",\"blockers\":[" s)
    (loop for blocker in (ege-blockers result)
          for idx from 0 do
            (when (> idx 0) (write-string "," s))
            (emit-json-string blocker s))
    (write-string "]" s)
    (write-string ",\"remediation_commands\":[" s)
    (loop for cmd in (ege-remediation-commands result)
          for idx from 0 do
            (when (> idx 0) (write-string "," s))
            (emit-json-string cmd s))
    (write-string "]" s)
    (write-string ",\"detail\":" s)
    (emit-json-string (ege-detail result) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (ege-timestamp result))
    (write-string "}" s)))
