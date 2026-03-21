(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (let* ((root (getenv-or "TUI_EVIDENCE_DIR" "test-results/tui-regression-matrix/complete/"))
           (cmd (getenv-or "TUI_EVIDENCE_COMMAND" "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
           (res (orrery/adapter:evaluate-mcp-tui-unified-envelope-gate-adapter root cmd)))
      (format t "~A~%" (orrery/adapter:mcp-tui-gate-adapter-result->json res))
      (unless (orrery/adapter:mtgar-pass-p res)
        (uiop:quit 1)))
  (error (e)
    (format *error-output* "~&MCP-TUI GATE ADAPTER ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
