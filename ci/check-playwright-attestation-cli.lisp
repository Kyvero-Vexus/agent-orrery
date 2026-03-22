;;; check-playwright-attestation-cli.lisp — Playwright S1-S6 attestation CLI

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(let* ((root (getenv-or "WEB_EVIDENCE_DIR" "test-results/e2e-artifacts/"))
       (cmd (getenv-or "WEB_EVIDENCE_COMMAND" "cd e2e && ./run-e2e.sh"))
       (out (getenv-or "WEB_ATTESTATION_OUT" "test-results/e2e-report/epic4-attestation-cli.json"))
       (report (orrery/adapter:write-playwright-attestation-cli-report root cmd out)))
  (format t "~A~%" (orrery/adapter:playwright-attestation-cli-report->json report))
  (unless (orrery/adapter:pacr-pass-p report)
    (uiop:quit 1)))

(uiop:quit 0)
