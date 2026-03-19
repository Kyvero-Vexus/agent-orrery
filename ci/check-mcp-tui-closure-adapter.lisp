(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "TUI_EVIDENCE_DIR") "test-results/tui-artifacts/"))
       (cmd (or (uiop:getenv "TUI_EVIDENCE_COMMAND") "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
       (r (orrery/adapter:evaluate-mcp-tui-closure-adapter root cmd)))
  (format t "~A~%" (orrery/adapter:tui-closure-report->json r))
  (unless (orrery/adapter:tcr-pass-p r)
    (uiop:quit 1)))

(uiop:quit 0)
