(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "WEB_EVIDENCE_DIR") "test-results/e2e-artifacts/"))
       (cmd (or (uiop:getenv "WEB_EVIDENCE_COMMAND") "cd e2e && ./run-e2e.sh"))
       (r (orrery/adapter:evaluate-playwright-lockstep root cmd)))
  (format t "~A~%" (orrery/adapter:playwright-lockstep-result->json r))
  (unless (orrery/adapter:plr-pass-p r)
    (uiop:quit 1)))

(uiop:quit 0)
