;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic4-fail-closed-gate.lisp — fail-closed Epic 4 gate for Playwright S1-S6
;;; Bead: agent-orrery-k2np

(in-package #:orrery/adapter)

(defstruct (epic4-fail-closed-result (:conc-name e4fcr-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string) (values epic4-fail-closed-result &optional))
        evaluate-epic4-fail-closed-gate)
 (ftype (function (epic4-fail-closed-result) (values string &optional))
        epic4-fail-closed-result->json))

(defun %scenario-has-kind-p (manifest scenario-id kind)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id)
           (type evidence-artifact-kind kind))
  (not (null (find-if (lambda (artifact)
                        (and (string= scenario-id (ea-scenario-id artifact))
                             (eq kind (ea-artifact-kind artifact))
                             (ea-present-p artifact)))
                      (rem-artifacts manifest)))))

(defun %missing-s1-s6-screenshot-or-trace (manifest)
  (declare (type runner-evidence-manifest manifest))
  (let ((missing nil))
    (dolist (sid *playwright-required-scenarios*)
      (unless (and (%scenario-has-kind-p manifest sid :screenshot)
                   (%scenario-has-kind-p manifest sid :trace))
        (push sid missing)))
    (nreverse missing)))

(defun evaluate-epic4-fail-closed-gate (artifacts-dir command)
  "Fail-closed Epic 4 gate:
- Playwright evidence only
- S1-S6 required
- screenshot+trace required per scenario
- deterministic command required"
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((manifest (compile-playwright-evidence-manifest artifacts-dir command))
         (report (verify-runner-evidence
                  manifest
                  *default-web-scenarios*
                  *web-required-artifacts*
                  '(:machine-report)
                  *expected-web-command*))
         (missing (%missing-s1-s6-screenshot-or-trace manifest))
         (command-ok (string= command *playwright-deterministic-command*))
         (pass (and (ecr-pass-p report)
                    command-ok
                    (null missing))))
    (make-epic4-fail-closed-result
     :pass-p pass
     :command-match-p command-ok
     :missing-scenarios missing
     :detail (format nil "pass=~A command_ok=~A missing=~D"
                     pass command-ok (length missing))
     :timestamp (get-universal-time))))

(defun epic4-fail-closed-result->json (result)
  (declare (type epic4-fail-closed-result result))
  (format nil
          "{\"pass\":~A,\"command_match\":~A,\"missing\":~D,\"detail\":\"~A\",\"timestamp\":~D}"
          (if (e4fcr-pass-p result) "true" "false")
          (if (e4fcr-command-match-p result) "true" "false")
          (length (e4fcr-missing-scenarios result))
          (e4fcr-detail result)
          (e4fcr-timestamp result)))
