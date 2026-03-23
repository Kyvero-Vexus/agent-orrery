;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; check-tui-continuity-preflight.lisp — CI gate for T1-T6 continuity preflight
;;; Bead: agent-orrery-6oh
;;;
;;; Usage:
;;;   TUI_EVIDENCE_DIR=<dir> TUI_EVIDENCE_COMMAND=<cmd> sbcl --script ci/check-tui-continuity-preflight.lisp
;;;
;;; Exits 0 on pass, 1 on fail.

(load "/home/slime/quicklisp/setup.lisp")
(ql:quickload :agent-orrery :silent t)

(let* ((root    (or (uiop:getenv "TUI_EVIDENCE_DIR")
                    "test-results/tui-artifacts/"))
       (command (or (uiop:getenv "TUI_EVIDENCE_COMMAND")
                    "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
       (verdict (orrery/adapter:run-tui-continuity-preflight root command))
       (json    (orrery/adapter:tui-continuity-verdict->json verdict)))
  (format t "~A~%" json)
  (unless (orrery/adapter:tcv-pass-p verdict)
    (uiop:quit 1)))
