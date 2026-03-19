;;; notarize-epic4-evidence.lisp — emit fail-closed Playwright notarization payload

(require :asdf)
(asdf:load-system "agent-orrery")

(let* ((artifact (or (uiop:getenv "WEB_ARTIFACT_ROOT") "test-results/e2e-artifacts"))
       (command (or (uiop:getenv "WEB_E2E_COMMAND") "cd e2e && ./run-e2e.sh"))
       (note (orrery/adapter:write-playwright-evidence-notarization artifact command)))
  (format t "~A~%" (orrery/adapter:playwright-evidence-notarization->json note))
  (unless (orrery/adapter:pen-complete-p note)
    (uiop:quit 1)))
