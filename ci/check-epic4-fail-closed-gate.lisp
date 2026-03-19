(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "WEB_EVIDENCE_DIR") "test-results/e2e-artifacts/"))
       (cmd (or (uiop:getenv "WEB_EVIDENCE_COMMAND") "cd e2e && ./run-e2e.sh"))
       (result (orrery/adapter:evaluate-epic4-fail-closed-gate root cmd)))
  (format t "~A~%" (orrery/adapter:epic4-fail-closed-result->json result))
  (unless (orrery/adapter:e4fcr-pass-p result)
    (uiop:quit 1)))

(uiop:quit 0)
