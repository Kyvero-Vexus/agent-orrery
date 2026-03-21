;;; check-mcp-tui-unified-envelope.lisp — deterministic Epic3 unified-envelope projector verifier

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (let* ((root (getenv-or "TUI_EVIDENCE_DIR" "test-results/tui-regression-matrix/complete/"))
           (cmd (getenv-or "TUI_EVIDENCE_COMMAND" "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
           (rep (orrery/adapter:project-mcp-tui-unified-envelope root cmd)))
      (format t "~A~%" (orrery/adapter:mcp-tui-envelope-report->json rep))
      (unless (orrery/adapter:mtep-pass-p rep)
        (uiop:quit 1)))
  (error (e)
    (format *error-output* "~&MCP-TUI ENVELOPE PROJECTOR ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
