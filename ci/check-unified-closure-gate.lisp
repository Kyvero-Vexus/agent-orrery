;;; check-unified-closure-gate.lisp — unified closure gate compiler + deterministic verification command

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (let* ((web-dir (getenv-or "WEB_EVIDENCE_DIR" "test-results/e2e-regression-matrix/complete/"))
           (web-cmd (getenv-or "WEB_EVIDENCE_COMMAND" "cd e2e && ./run-e2e.sh"))
           (tui-dir (getenv-or "TUI_EVIDENCE_DIR" "test-results/tui-regression-matrix/complete/"))
           (tui-cmd (getenv-or "TUI_EVIDENCE_COMMAND" "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
           (bundle (orrery/adapter:evaluate-unified-preflight-bundle web-dir web-cmd tui-dir tui-cmd))
           (pass (orrery/adapter:upb-overall-pass-p bundle))
           (verify-cmd "make web-fixture-regression tui-fixture-regression unified-preflight"))
      (format t "{\"pass\":~A,\"deterministic_verification_command\":\"~A\",\"bundle\":~A}~%"
              (if pass "true" "false") verify-cmd
              (orrery/adapter:unified-preflight-bundle->json bundle))
      (unless pass
        (uiop:quit 1)))
  (error (e)
    (format *error-output* "~&UNIFIED CLOSURE GATE ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
