(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "WEB_EVIDENCE_DIR") "test-results/e2e-artifacts/"))
       (cmd (or (uiop:getenv "WEB_EVIDENCE_COMMAND") "cd e2e && ./run-e2e.sh"))
       (lock (orrery/adapter:build-playwright-evidence-lock root cmd)))
  (format t "~A~%" (orrery/adapter:playwright-evidence-lock->json lock))
  (unless (orrery/adapter:pel-pass-p lock)
    (uiop:quit 1)))

(uiop:quit 0)
