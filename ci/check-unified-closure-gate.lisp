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
           (tui-baseline (getenv-or "TUI_BASELINE_ARTIFACTS_DIR" tui-dir))
           (out (getenv-or "UNIFIED_CLOSURE_OUT" "artifacts/preflight/unified-closure-acceptance.json"))
           #+sbcl (old-baseline (uiop:getenv "TUI_BASELINE_ARTIFACTS_DIR"))
           bundle gate-adapter pass verify-cmd json)
      #+sbcl (sb-posix:setenv "TUI_BASELINE_ARTIFACTS_DIR" tui-baseline 1)
      (setf bundle (orrery/adapter:evaluate-unified-preflight-bundle web-dir web-cmd tui-dir tui-cmd)
            gate-adapter (orrery/adapter:evaluate-mcp-tui-unified-envelope-gate-adapter tui-dir tui-cmd)
            pass (and (orrery/adapter:upb-overall-pass-p bundle)
                      (orrery/adapter:mtgar-pass-p gate-adapter))
            verify-cmd "make web-fixture-regression tui-fixture-regression unified-preflight unified-closure-gate"
            json (format nil "{\"pass\":~A,\"deterministic_verification_command\":\"~A\",\"tui_baseline_artifacts_dir\":\"~A\",\"bundle\":~A,\"gate_adapter\":~A}"
                         (if pass "true" "false") verify-cmd tui-baseline
                         (orrery/adapter:unified-preflight-bundle->json bundle)
                         (orrery/adapter:mcp-tui-gate-adapter-result->json gate-adapter)))
      (ensure-directories-exist out)
      (with-open-file (o out :direction :output :if-exists :supersede)
        (write-string json o))
      (format t "~A~%" json)
      #+sbcl (if old-baseline
                 (sb-posix:setenv "TUI_BASELINE_ARTIFACTS_DIR" old-baseline 1)
                 (sb-posix:unsetenv "TUI_BASELINE_ARTIFACTS_DIR"))
      (unless pass
        (uiop:quit 1)))
  (error (e)
    (format *error-output* "~&UNIFIED CLOSURE GATE ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
