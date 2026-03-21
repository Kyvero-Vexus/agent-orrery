(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "TUI_EVIDENCE_DIR") "test-results/tui-artifacts/"))
       (cmd (or (uiop:getenv "TUI_EVIDENCE_COMMAND") "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
       (out (or (uiop:getenv "TUI_WITNESS_OUTPUT") "test-results/tui-evidence-report/epic3-witness-bundle.json"))
       (bundle (orrery/adapter:write-mcp-tui-witness-bundle root cmd out)))
  (format t "~A~%" (orrery/adapter:mcp-tui-witness-bundle->json bundle))
  (unless (orrery/adapter:mtwb-pass-p bundle)
    (uiop:quit 1)))

(uiop:quit 0)
