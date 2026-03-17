;;; check-evidence-recertification.lisp — release evidence re-certification gate

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((ws (getenv-or "WEB_STORED_DIR" "test-results/e2e-report/"))
             (wr (getenv-or "WEB_REGEN_DIR" "test-results/e2e-report/"))
             (ts (getenv-or "TUI_STORED_DIR" "test-results/tui-artifacts/"))
             (tr (getenv-or "TUI_REGEN_DIR" "test-results/tui-artifacts/"))
             (wc (getenv-or "WEB_EVIDENCE_COMMAND" "cd e2e && ./run-e2e.sh"))
             (tc (getenv-or "TUI_EVIDENCE_COMMAND" "make e2e-tui"))
             (pkg (find-package "ORRERY/ADAPTER"))
             (eval-sym (and pkg (find-symbol "EVALUATE-EVIDENCE-RECERTIFICATION-GATE" pkg)))
             (ok-sym (and pkg (find-symbol "ERR-OVERALL-PASS-P" pkg)))
             (json-sym (and pkg (find-symbol "EVIDENCE-RECERTIFICATION-RESULT->JSON" pkg)))
             (res (and eval-sym (funcall eval-sym ws wr ts tr wc tc)))
             (ok (and res ok-sym (funcall ok-sym res))))
        (format t "~A~%" (if (and res json-sym)
                              (funcall json-sym res)
                              "{\"error\":\"recertification-symbols-missing\"}"))
        (unless ok
          (error "Evidence recertification gate failed"))))
  (error (e)
    (format *error-output* "~&EVIDENCE RECERTIFICATION ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
