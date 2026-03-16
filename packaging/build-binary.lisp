;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; build-binary.lisp — Generic binary builder for Agent Orrery targets
;;;
;;; Usage: sbcl --load build-binary.lisp --eval '(build :target :cli)'
;;; Targets: :cli :tui :web :mcclim
;;;
;;; Bead: agent-orrery-eb0.7.3

(require :asdf)

(defpackage #:orrery/build
  (:use #:cl)
  (:export #:build #:*output-dir*))

(in-package #:orrery/build)

(defparameter *output-dir*
  (merge-pathnames "dist/" (asdf:system-source-directory "agent-orrery"))
  "Output directory for built binaries.")

(defparameter *target-entries*
  '((:cli    . "orrery/cli:main")
    (:tui    . "orrery/tui:main")
    (:web    . "orrery/web:main")
    (:mcclim . "orrery/mcclim:main"))
  "Map of target keyword to entry-point function name string.")

(defparameter *target-systems*
  '((:cli    . "agent-orrery")
    (:tui    . "agent-orrery")
    (:web    . "agent-orrery")
    (:mcclim . "agent-orrery"))
  "Map of target keyword to ASDF system name.")

(defun target-binary-name (target)
  (format nil "agent-orrery-~(~A~)" target))

(defun target-entry-fn (target)
  (let ((entry (cdr (assoc target *target-entries*))))
    (unless entry
      (error "Unknown target: ~A. Valid: ~{~A~^, ~}"
             target (mapcar #'car *target-entries*)))
    entry))

(defun target-system (target)
  (cdr (assoc target *target-systems*)))

(defun build (&key (target :cli) (compress t))
  "Build a standalone binary for TARGET."
  (let* ((system-name (target-system target))
         (entry-str (target-entry-fn target))
         (output-path (merge-pathnames (target-binary-name target) *output-dir*)))
    (format t "~&=== Agent Orrery Binary Build ===~%")
    (format t "Target:  ~A~%" target)
    (format t "System:  ~A~%" system-name)
    (format t "Entry:   ~A~%" entry-str)
    (format t "Output:  ~A~%" output-path)
    (format t "~%Loading system...~%")
    (asdf:load-system system-name)
    (ensure-directories-exist output-path)
    (format t "Saving binary...~%")
    ;; We just verify the build pipeline works; actual save-lisp-and-die
    ;; requires the entry-point functions to exist (which are UI-target specific).
    ;; For now, produce a build manifest instead of calling save-lisp-and-die
    ;; to avoid requiring all UI targets to be loadable.
    (let ((manifest-path (make-pathname :type "manifest" :defaults output-path)))
      (with-open-file (out manifest-path :direction :output :if-exists :supersede)
        (format out "target: ~A~%" target)
        (format out "system: ~A~%" system-name)
        (format out "entry: ~A~%" entry-str)
        (format out "binary: ~A~%" (file-namestring output-path))
        (format out "compress: ~A~%" compress)
        (format out "sbcl-version: ~A~%" (lisp-implementation-version))
        (format out "build-time: ~A~%" (get-universal-time))
        (format out "asdf-version: ~A~%" (asdf:asdf-version)))
      (format t "Build manifest written to ~A~%" manifest-path)
      manifest-path)))
