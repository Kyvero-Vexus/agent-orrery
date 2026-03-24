;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; build-tui-core.lisp — Build precompiled SBCL image for TUI E2E testing
;;;
;;; Usage:
;;;   sbcl --load scripts/build-tui-core.lisp
;;;
;;; Produces:
;;;   artifacts/tui-core.core  — precompiled SBCL image with agent-orrery loaded
;;;
;;; The core reduces TUI E2E startup from ~31s to <5s by pre-loading:
;;;   - Quicklisp
;;;   - agent-orrery system (all components)
;;;   - agent-orrery/test-harness (fixture-adapter, clock, timeline, generators)
;;;   - parachute (test framework for harness)
;;;
;;; Startup with precompiled core:
;;;   sbcl --core artifacts/tui-core.core \
;;;        --eval "(orrery/tui-core:launch-dashboard)"

(declaim (optimize (safety 2) (speed 1) (debug 1)))

(let ((ql-setup (merge-pathnames "quicklisp/setup.lisp"
                                 (user-homedir-pathname))))
  (unless (probe-file ql-setup)
    (error "Quicklisp setup not found at ~A" ql-setup))
  (load ql-setup))

;; Determine project root (this script lives in scripts/ one level below root)
(defvar *project-root*
  (truename
   (merge-pathnames "../"
                    (make-pathname :directory
                                   (pathname-directory *load-truename*)))))

(format t "~&[build-tui-core] Project root: ~A~%" *project-root*)

;; Make ASDF find agent-orrery
(pushnew *project-root* asdf:*central-registry* :test #'equal)

(format t "~&[build-tui-core] Loading agent-orrery...~%")
(ql:quickload :parachute :silent t)
(asdf:load-system "agent-orrery/test-harness")

(format t "~&[build-tui-core] All systems loaded. Defining toplevel...~%")

;; Define the package and launch function that the core will call on startup
(defpackage #:orrery/tui-core
  (:use #:cl)
  (:export #:launch-dashboard))

(in-package #:orrery/tui-core)

(defun launch-dashboard ()
  "Entry point for precompiled TUI core. Builds fixture adapter and starts dashboard."
  (declare (optimize (safety 2) (speed 1)))
  (let* ((adapter (orrery/harness:make-fixture-adapter))
         (store   (orrery/store:snapshot-from-adapter adapter)))
    (orrery/tui:start-dashboard :store store)))

(in-package #:cl-user)

;; Ensure artifacts directory exists
(ensure-directories-exist
 (merge-pathnames "artifacts/" *project-root*))

(defvar *core-path*
  (merge-pathnames "artifacts/tui-core.core" *project-root*))

(format t "~&[build-tui-core] Saving core to ~A...~%" *core-path*)

(sb-ext:save-lisp-and-die
 (namestring *core-path*)
 :toplevel nil          ; No auto-toplevel; caller uses --eval
 :executable nil        ; Pure core, not standalone executable
 :save-runtime-options nil
 :compression nil)
