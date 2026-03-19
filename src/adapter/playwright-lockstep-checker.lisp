;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-lockstep-checker.lisp — deterministic S1-S6 scenario-contract lockstep checker
;;; Bead: agent-orrery-3dd4

(in-package #:orrery/adapter)

(defstruct (playwright-lockstep-result (:conc-name plr-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string) (values playwright-lockstep-result &optional))
        evaluate-playwright-lockstep)
 (ftype (function (playwright-lockstep-result) (values string &optional))
        playwright-lockstep-result->json))

(defun %required-scenarios-present-p (manifest)
  (declare (type runner-evidence-manifest manifest))
  (let ((missing nil))
    (dolist (sid *playwright-required-scenarios*)
      (let ((shot (find-if (lambda (a)
                             (and (string= sid (ea-scenario-id a))
                                  (eq :screenshot (ea-artifact-kind a))
                                  (ea-present-p a)))
                           (rem-artifacts manifest)))
            (trace (find-if (lambda (a)
                              (and (string= sid (ea-scenario-id a))
                                   (eq :trace (ea-artifact-kind a))
                                   (ea-present-p a)))
                            (rem-artifacts manifest))))
        (unless (and shot trace)
          (push sid missing))))
    (nreverse missing)))

(defun evaluate-playwright-lockstep (artifacts-dir command)
  "Fail-closed lockstep check for Epic 4 / eb0.4.5 lineage.
Requires Playwright S1-S6 screenshot+trace artifacts and deterministic command." 
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((manifest (compile-playwright-evidence-manifest artifacts-dir command))
         (missing (%required-scenarios-present-p manifest))
         (command-ok (canonical-playwright-command-p command))
         (pass (and command-ok (null missing))))
    (make-playwright-lockstep-result
     :pass-p pass
     :command-match-p command-ok
     :missing-scenarios missing
     :detail (format nil "command_ok=~A missing=~D" command-ok (length missing))
     :timestamp (get-universal-time))))

(defun playwright-lockstep-result->json (result)
  (declare (type playwright-lockstep-result result))
  (format nil
          "{\"pass\":~A,\"command_match\":~A,\"missing\":~D,\"detail\":\"~A\",\"timestamp\":~D}"
          (if (plr-pass-p result) "true" "false")
          (if (plr-command-match-p result) "true" "false")
          (length (plr-missing-scenarios result))
          (plr-detail result)
          (plr-timestamp result)))
