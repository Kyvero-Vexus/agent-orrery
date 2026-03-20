(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "TUI_EVIDENCE_DIR") "test-results/tui-artifacts/"))
       (cmd (or (uiop:getenv "TUI_EVIDENCE_COMMAND") "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
       (v (orrery/adapter:evaluate-mcp-tui-replay-verdict root cmd)))
  (format t "~A~%" (orrery/adapter:mcp-tui-replay-verdict->json v))
  (unless (orrery/adapter:mtrv-pass-p v)
    (uiop:quit 1)))

(uiop:quit 0)
