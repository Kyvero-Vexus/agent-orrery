;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-pack-index.lisp — deterministic Playwright evidence pack index
;;; Bead: agent-orrery-z7xe

(in-package #:orrery/adapter)

(defstruct (playwright-evidence-pack-index (:conc-name pepi-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (scenario-count 0 :type integer)
  (artifact-count 0 :type integer)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string) (values boolean &optional)) canonical-playwright-command-p)
 (ftype (function (string string) (values playwright-evidence-pack-index &optional))
        build-playwright-evidence-pack-index)
 (ftype (function (playwright-evidence-pack-index) (values string &optional))
        playwright-evidence-pack-index->json))

(defun canonical-playwright-command-p (command)
  (declare (type string command))
  (or (string= command *playwright-deterministic-command*)
      (string= command "bash run-e2e.sh")
      (string= command "cd e2e && bash run-e2e.sh")))

(defun %missing-s1-s6 (manifest)
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

(defun build-playwright-evidence-pack-index (artifacts-dir command)
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((manifest (compile-playwright-evidence-manifest artifacts-dir command))
         (missing (%missing-s1-s6 manifest))
         (command-ok (canonical-playwright-command-p command))
         (scenario-count (length *playwright-required-scenarios*))
         (artifact-count (length (rem-artifacts manifest)))
         (pass (and command-ok (null missing))))
    (make-playwright-evidence-pack-index
     :pass-p pass
     :command-match-p command-ok
     :scenario-count scenario-count
     :artifact-count artifact-count
     :missing-scenarios missing
     :detail (format nil "command_ok=~A missing=~D artifacts=~D"
                     command-ok (length missing) artifact-count)
     :timestamp (get-universal-time))))

(defun playwright-evidence-pack-index->json (index)
  (declare (type playwright-evidence-pack-index index))
  (format nil
          "{\"pass\":~A,\"command_match\":~A,\"scenario_count\":~D,\"artifact_count\":~D,\"missing\":~D,\"detail\":\"~A\",\"timestamp\":~D}"
          (if (pepi-pass-p index) "true" "false")
          (if (pepi-command-match-p index) "true" "false")
          (pepi-scenario-count index)
          (pepi-artifact-count index)
          (length (pepi-missing-scenarios index))
          (pepi-detail index)
          (pepi-timestamp index)))
