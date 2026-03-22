;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; check-playwright-cmd-table-verifier.lisp — CI runner for S1-S6 command-table verifier gate
;;; Bead: agent-orrery-91gj
;;;
;;; Usage:
;;;   WEB_EVIDENCE_DIR=<dir> WEB_EVIDENCE_COMMAND=<cmd> sbcl --script ci/check-playwright-cmd-table-verifier.lisp
;;;
;;; Exits 0 on pass, 1 on fail/error.

(load "/home/slime/quicklisp/setup.lisp")
(ql:quickload :agent-orrery :silent t)

(let* ((artifact-root (or (uiop:getenv "WEB_EVIDENCE_DIR")
                          "test-results/e2e-regression-matrix/complete/"))
       (command (or (uiop:getenv "WEB_EVIDENCE_COMMAND")
                    "cd e2e && ./run-e2e.sh"))
       (ledger (ignore-errors
                 (orrery/adapter:write-playwright-scenario-ledger artifact-root command)))
       (verdict (orrery/adapter:verify-playwright-command-table ledger))
       (json (orrery/adapter:playwright-cmd-table-verdict->json verdict)))
  (format t "~A~%" json)
  (unless (orrery/adapter:pctv-pass-p verdict)
    (uiop:quit 1)))
