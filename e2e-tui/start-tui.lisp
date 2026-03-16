;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; start-tui.lisp — Launch Agent Orrery TUI for E2E testing
;;;
;;; Usage:  sbcl --load e2e-tui/start-tui.lisp
;;;
;;; Loads the agent-orrery system with fixture adapter (deterministic data)
;;; and starts the TUI dashboard in the terminal provided by the PTY.

(load "/home/slime/quicklisp/setup.lisp")

;; Suppress compilation noise
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (ql:quickload :agent-orrery :silent t))

;; Load test-harness for fixture-adapter
;; packages.lisp also defines orrery/harness-tests which uses parachute
(ql:quickload :parachute :silent t)
(let* ((base (asdf:system-source-directory "agent-orrery")))
  (load (merge-pathnames "test-harness/packages.lisp" base))
  (load (merge-pathnames "test-harness/clock.lisp" base))
  (load (merge-pathnames "test-harness/timeline.lisp" base))
  (load (merge-pathnames "test-harness/generators.lisp" base))
  (load (merge-pathnames "test-harness/conformance.lisp" base))
  (load (merge-pathnames "test-harness/fixture-adapter.lisp" base)))

;; Build fixture adapter → sync-store → start TUI
(let* ((adapter (orrery/harness:make-fixture-adapter))
       (store (orrery/store:snapshot-from-adapter adapter)))
  (orrery/tui:start-dashboard :store store))
