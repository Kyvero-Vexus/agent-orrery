;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; run-tests.lisp — CI test runner for Agent Orrery
;;;
;;; Exit codes:
;;;   0 — all tests passed
;;;   1 — some tests failed
;;;   2 — load error
;;;
;;; Usage:
;;;   sbcl --load ci/run-tests.lisp

(require :asdf)

(let* ((local-ql (merge-pathnames "setup.lisp" (pathname "ci/.quicklisp/")))
       (home-ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (cond ((probe-file local-ql) (load local-ql))
        ((probe-file home-ql) (load home-ql))
        (t (format *error-output* "~&LOAD ERROR: Quicklisp setup not found. Run: sbcl --script ci/bootstrap-quicklisp.lisp~%")
           (sb-ext:exit :code 2))))

;; Try workspace-local path first, then current directory
(dolist (path (list #P"/home/slime/projects/agent-orrery/"
                    (truename ".")))
  (pushnew path asdf:*central-registry* :test #'equal))

(asdf:clear-source-registry)

(format t "~&=== Agent Orrery Test Suite ===~%~%")

(handler-case
    (asdf:load-system :agent-orrery/test-harness)
  (error (e)
    (format *error-output* "~&LOAD ERROR: ~A~%" e)
    (sb-ext:exit :code 2)))

(let* ((r (parachute:test (find-package :orrery/harness-tests)
                          :report 'parachute:plain))
       (s (parachute:status r)))
  (format t "~&~%=== Result: ~A ===~%" s)
  (sb-ext:exit :code (if (eq s :passed) 0 1)))
