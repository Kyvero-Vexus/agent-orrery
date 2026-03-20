(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((out (or (uiop:getenv "TUI_FIXTURE_DIR") "test-results/tui-artifacts/"))
       (mode (if (string= (or (uiop:getenv "TUI_FIXTURE_MODE") "complete") "gapped") :gapped :complete))
       (res (orrery/adapter:generate-tui-fixture-set out mode)))
  (format t "~A~%" (orrery/adapter:tui-fixture-generation-result->json res))
  (unless (orrery/adapter:tfgr-pass-p res)
    (uiop:quit 1)))

(uiop:quit 0)
