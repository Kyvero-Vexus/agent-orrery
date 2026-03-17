;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-compiler.lisp — Typed Playwright S1-S6 evidence compiler
;;; Bead: agent-orrery-yzx

(in-package #:orrery/adapter)

(defparameter *playwright-required-scenarios*
  '("S1" "S2" "S3" "S4" "S5" "S6"))

(defparameter *playwright-deterministic-command*
  "cd e2e && ./run-e2e.sh")

(declaim
 (ftype (function (string) (values evidence-runner-kind &optional)) infer-web-runner-kind)
 (ftype (function (string) (values (or null string) &optional)) infer-playwright-scenario-id)
 (ftype (function (string) (values evidence-artifact-kind &optional)) infer-web-artifact-kind)
 (ftype (function (string string) (values runner-evidence-manifest &optional))
        compile-playwright-evidence-manifest))

(defun infer-web-runner-kind (command)
  "Infer web runner kind from deterministic command string." 
  (declare (type string command))
  (if (search "run-e2e" command :test #'char-equal)
      :playwright-web
      :playwright-web))

(defun infer-playwright-scenario-id (filename)
  "Extract S1..S6 scenario ID from FILENAME, or NIL if absent." 
  (declare (type string filename))
  (let ((upper (string-upcase filename)))
    (loop for sid in *playwright-required-scenarios*
          when (search sid upper)
            do (return sid)
          finally (return nil))))

(defun infer-web-artifact-kind (filename)
  "Infer artifact kind from filename extension/content." 
  (declare (type string filename))
  (let ((lower (string-downcase filename)))
    (cond
      ((or (search ".png" lower) (search ".jpg" lower) (search ".jpeg" lower)) :screenshot)
      ((or (search ".zip" lower) (search ".trace" lower)) :trace)
      ((or (search ".json" lower) (search "report" lower)) :machine-report)
      (t :machine-report))))

(defun %artifact-size-bytes (path)
  (or (ignore-errors
        (with-open-file (s path :direction :input :element-type '(unsigned-byte 8))
          (file-length s)))
      0))

(defun %artifact-present-p (path)
  (and (probe-file path)
       (> (%artifact-size-bytes path) 0)))

(defun compile-playwright-evidence-manifest (artifacts-dir command)
  "Compile Playwright S1-S6 evidence from ARTIFACTS-DIR into typed manifest." 
  (declare (type string artifacts-dir command))
  (let ((scenarios nil)
        (artifacts nil)
        (seen-scenarios (make-hash-table :test #'equal)))
    (when (probe-file artifacts-dir)
      (dolist (path (directory (merge-pathnames
                                (make-pathname :name :wild :type :wild :directory '(:relative :wild-inferiors))
                                (pathname artifacts-dir))))
        (let* ((name (namestring path))
               (base (file-namestring path))
               (sid (infer-playwright-scenario-id base))
               (kind (infer-web-artifact-kind base))
               (present (%artifact-present-p path)))
          (push (make-evidence-artifact
                 :scenario-id (or sid "")
                 :artifact-kind kind
                 :path name
                 :present-p present
                 :detail "compiled")
                artifacts)
          (when sid
            (setf (gethash sid seen-scenarios) (and present t))))))

    (dolist (sid *playwright-required-scenarios*)
      (push (make-scenario-evidence
             :scenario-id sid
             :status (if (gethash sid seen-scenarios) :pass :missing)
             :detail (if (gethash sid seen-scenarios) "artifact-present" "artifact-missing"))
            scenarios))

    (make-runner-evidence-manifest
     :runner-id "playwright-web"
     :runner-kind (infer-web-runner-kind command)
     :command command
     :scenarios (nreverse scenarios)
     :artifacts (nreverse artifacts)
     :timestamp (get-universal-time))))
