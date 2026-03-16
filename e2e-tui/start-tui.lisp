;;; Start TUI dashboard for E2E testing
(require :sb-posix)
;; Suppress all startup noise
(setf *standard-output* (make-broadcast-stream))
(setf *error-output* (make-broadcast-stream))
(setf *trace-output* (make-broadcast-stream))
(load "/home/slime/quicklisp/setup.lisp")
(ql:quickload :agent-orrery :silent t)
;; Restore output for TUI
(setf *standard-output* (sb-sys:make-fd-stream 1 :output t :name "stdout"))
(setf *error-output* (sb-sys:make-fd-stream 2 :output t :name "stderr"))
;; Run
(orrery/tui:run-tui)
