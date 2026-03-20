;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-locker.lisp — Epic 4 S1-S6 evidence lock bundle + recheck
;;; Bead: agent-orrery-8cvx

(in-package #:orrery/adapter)

(defstruct (playwright-evidence-lock (:conc-name pel-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (command "" :type string)
  (artifact-count 0 :type integer)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string) (values playwright-evidence-lock &optional))
        build-playwright-evidence-lock)
 (ftype (function (playwright-evidence-lock) (values string &optional))
        playwright-evidence-lock->json))

(defun %missing-s1-s6-for-lock (manifest)
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

(defun build-playwright-evidence-lock (artifacts-dir command)
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((manifest (compile-playwright-evidence-manifest artifacts-dir command))
         (missing (%missing-s1-s6-for-lock manifest))
         (command-ok (canonical-playwright-command-p command))
         (pass (and command-ok (null missing))))
    (make-playwright-evidence-lock
     :pass-p pass
     :command-match-p command-ok
     :command command
     :artifact-count (length (rem-artifacts manifest))
     :missing-scenarios missing
     :detail (format nil "command_ok=~A missing=~D artifacts=~D"
                     command-ok (length missing) (length (rem-artifacts manifest)))
     :timestamp (get-universal-time))))

(defun playwright-evidence-lock->json (lock)
  (declare (type playwright-evidence-lock lock))
  (format nil
          "{\"pass\":~A,\"command_match\":~A,\"command\":\"~A\",\"artifact_count\":~D,\"missing\":~D,\"detail\":\"~A\",\"timestamp\":~D}"
          (if (pel-pass-p lock) "true" "false")
          (if (pel-command-match-p lock) "true" "false")
          (pel-command lock)
          (pel-artifact-count lock)
          (length (pel-missing-scenarios lock))
          (pel-detail lock)
          (pel-timestamp lock)))
