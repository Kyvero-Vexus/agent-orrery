(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (let* ((root (getenv-or "WEB_EVIDENCE_DIR" "test-results/e2e-regression-matrix/complete/"))
           (cmd (getenv-or "WEB_EVIDENCE_COMMAND" "cd e2e && ./run-e2e.sh"))
           (res (orrery/adapter:evaluate-playwright-ingestion-adapter root cmd)))
      (format t "~A~%" (orrery/adapter:playwright-ingestion-result->json res))
      (unless (orrery/adapter:pwir-pass-p res)
        (uiop:quit 1)))
  (error (e)
    (format *error-output* "~&PLAYWRIGHT INGESTION ADAPTER ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
