;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-evidence-compiler.lisp — Typed mcp-tui-driver T1-T6 evidence compiler
;;; Bead: agent-orrery-y8p

(in-package #:orrery/adapter)

(defparameter *mcp-tui-required-scenarios*
  '("T1" "T2" "T3" "T4" "T5" "T6"))

(defparameter *mcp-tui-deterministic-command*
  "make e2e-tui")

(declaim
 (ftype (function (string) (values evidence-runner-kind &optional)) infer-tui-runner-kind)
 (ftype (function (string) (values (or null string) &optional)) infer-mcp-tui-scenario-id)
 (ftype (function (string) (values evidence-artifact-kind &optional)) infer-tui-artifact-kind)
 (ftype (function (string string) (values runner-evidence-manifest &optional))
        compile-mcp-tui-evidence-manifest))

(defun infer-tui-runner-kind (command)
  (declare (type string command))
  (if (search "e2e-tui" command :test #'char-equal)
      :mcp-tui-driver
      :mcp-tui-driver))

(defun infer-mcp-tui-scenario-id (filename)
  (declare (type string filename))
  (let ((upper (string-upcase filename)))
    (loop for sid in *mcp-tui-required-scenarios*
          when (search sid upper)
            do (return sid)
          finally (return nil))))

(defun infer-tui-artifact-kind (filename)
  (declare (type string filename))
  (let ((lower (string-downcase filename)))
    (cond
      ((or (search ".png" lower) (search ".jpg" lower) (search ".jpeg" lower)) :screenshot)
      ((or (search ".txt" lower) (search "transcript" lower)) :transcript)
      ((search ".cast" lower) :asciicast)
      ((or (search ".json" lower) (search "report" lower)) :machine-report)
      (t :machine-report))))

(defun %tui-artifact-size-bytes (path)
  (or (ignore-errors
        (with-open-file (s path :direction :input :element-type '(unsigned-byte 8))
          (file-length s)))
      0))

(defun %tui-artifact-present-p (path)
  (and (probe-file path)
       (> (%tui-artifact-size-bytes path) 0)))

(defun compile-mcp-tui-evidence-manifest (artifacts-dir command)
  "Compile mcp-tui-driver T1-T6 evidence from ARTIFACTS-DIR into typed manifest." 
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
               (sid (infer-mcp-tui-scenario-id base))
               (kind (infer-tui-artifact-kind base))
               (present (%tui-artifact-present-p path)))
          (push (make-evidence-artifact
                 :scenario-id (or sid "")
                 :artifact-kind kind
                 :path name
                 :present-p present
                 :detail "compiled")
                artifacts)
          (when sid
            (setf (gethash sid seen-scenarios) (and present t))))))

    (dolist (sid *mcp-tui-required-scenarios*)
      (push (make-scenario-evidence
             :scenario-id sid
             :status (if (gethash sid seen-scenarios) :pass :missing)
             :detail (if (gethash sid seen-scenarios) "artifact-present" "artifact-missing"))
            scenarios))

    (make-runner-evidence-manifest
     :runner-id "mcp-tui-driver"
     :runner-kind (infer-tui-runner-kind command)
     :command command
     :scenarios (nreverse scenarios)
     :artifacts (nreverse artifacts)
     :timestamp (get-universal-time))))
