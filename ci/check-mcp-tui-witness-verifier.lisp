(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "TUI_EVIDENCE_DIR") "test-results/tui-artifacts/"))
       (cmd (or (uiop:getenv "TUI_EVIDENCE_COMMAND") "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
       (bundle (orrery/adapter:evaluate-mcp-tui-witness-bundle root cmd))
       (verification (orrery/adapter:verify-mcp-tui-witness-bundle bundle cmd)))
  (format t "~A~%" (orrery/adapter:mcp-tui-witness-verification->json verification))
  (unless (orrery/adapter:mtwv-pass-p verification)
    (uiop:quit 1)))

(uiop:quit 0)
