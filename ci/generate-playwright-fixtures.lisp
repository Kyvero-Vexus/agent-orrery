(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((out (or (uiop:getenv "WEB_FIXTURE_DIR") "test-results/e2e-artifacts/"))
       (mode-env (string-downcase (or (uiop:getenv "WEB_FIXTURE_MODE") "complete")))
       (mode (cond
               ((string= mode-env "missing-trace") :missing-trace)
               ((string= mode-env "missing-scenario") :missing-scenario)
               ((string= mode-env "gapped") :missing-trace)
               (t :complete)))
       (res (orrery/adapter:generate-playwright-fixture-set out mode)))
  (format t "~A~%" (orrery/adapter:playwright-fixture-generation-result->json res))
  (unless (orrery/adapter:pfgr-pass-p res)
    (uiop:quit 1)))

(uiop:quit 0)
