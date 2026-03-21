(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "WEB_EVIDENCE_DIR") "test-results/e2e-artifacts/"))
       (cmd (or (uiop:getenv "WEB_E2E_COMMAND") "cd e2e && ./run-e2e.sh"))
       (out (or (uiop:getenv "WEB_WITNESS_OUTPUT") "test-results/e2e-report/epic4-witness-bundle.json"))
       (bundle (orrery/adapter:write-playwright-witness-bundle root cmd out)))
  (format t "~A~%" (orrery/adapter:playwright-witness-bundle->json bundle))
  (unless (orrery/adapter:pwb-pass-p bundle)
    (uiop:quit 1)))

(uiop:quit 0)
