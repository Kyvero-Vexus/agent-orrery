;;; check-t1-t6-continuity-preflight.lisp — deterministic T1-T6 continuity preflight CLI

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (let* ((artifact (getenv-or "TUI_EVIDENCE_DIR" "test-results/tui-artifacts/"))
           (command (getenv-or "TUI_EVIDENCE_COMMAND" "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
           (ledger-out (getenv-or "TUI_LEDGER_OUT" "test-results/tui-artifacts/t1-t6-scenario-ledger.json"))
           (ledger-prior (getenv-or "TUI_LEDGER_PRIOR" (format nil "~A.sexp" ledger-out)))
           (ledger (orrery/adapter:write-tui-scenario-ledger artifact command ledger-out
                                                            :previous-ledger-path ledger-prior))
           (pass (orrery/adapter:tsl-continuity-pass-p ledger)))
      (format t "{\"pass\":~A,\"detail\":~A,\"ledger\":~A}~%"
              (if pass "true" "false")
              (if pass "\"continuity-ok\"" "\"continuity-mismatch\"")
              (orrery/adapter:tui-scenario-ledger->json ledger))
      (unless pass
        (uiop:quit 1)))
  (error (e)
    (format *error-output* "~&T1-T6 CONTINUITY ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
