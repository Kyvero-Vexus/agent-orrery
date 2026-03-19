(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "WEB_EVIDENCE_DIR") "test-results/e2e-artifacts/"))
       (cmd (or (uiop:getenv "WEB_EVIDENCE_COMMAND") "cd e2e && ./run-e2e.sh"))
       (idx (orrery/adapter:build-playwright-evidence-pack-index root cmd)))
  (format t "~A~%" (orrery/adapter:playwright-evidence-pack-index->json idx))
  (unless (orrery/adapter:pepi-pass-p idx)
    (uiop:quit 1)))

(uiop:quit 0)
