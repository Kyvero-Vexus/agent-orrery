;;; check-playwright-s1-s6-bundle-verifier.lisp — Epic4 Playwright bundle verifier CLI

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (let* ((root (getenv-or "WEB_EVIDENCE_DIR" "test-results/e2e-report/"))
           (cmd (getenv-or "WEB_EVIDENCE_COMMAND" "cd e2e && ./run-e2e.sh"))
           (pre (orrery/adapter:run-playwright-s1-s6-preflight root cmd))
           (lock (orrery/adapter:build-playwright-evidence-lock root cmd))
           (pass (and (orrery/adapter:ppv-pass-p pre)
                      (orrery/adapter:pel-pass-p lock))))
      (format t "{\"pass\":~A,\"framework\":\"playwright\",\"required_scenarios\":[\"S1\",\"S2\",\"S3\",\"S4\",\"S5\",\"S6\"],\"required_artifacts\":[\"screenshot\",\"trace\"],\"preflight\":~A,\"evidence_lock\":~A}~%"
              (if pass "true" "false")
              (orrery/adapter:playwright-preflight-verdict->json pre)
              (orrery/adapter:playwright-evidence-lock->json lock))
      (unless pass
        (uiop:quit 1)))
  (error (e)
    (format *error-output* "~&PLAYWRIGHT BUNDLE VERIFIER ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
