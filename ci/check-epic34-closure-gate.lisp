;;; check-epic34-closure-gate.lisp — deny Epic 3/4 closure without required evidence

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((web-dir (getenv-or "WEB_EVIDENCE_DIR" "test-results/e2e-report/"))
             (web-cmd (getenv-or "WEB_EVIDENCE_COMMAND" "cd e2e && ./run-e2e.sh"))
             (tui-dir (getenv-or "TUI_EVIDENCE_DIR" "test-results/tui-artifacts/"))
             (tui-cmd (getenv-or "TUI_EVIDENCE_COMMAND" "make e2e-tui"))
             (pkg (find-package "ORRERY/ADAPTER"))
             (eval-sym (and pkg (find-symbol "EVALUATE-EPIC34-CLOSURE-GATE" pkg)))
             (ok-sym (and pkg (find-symbol "ECGR-OVERALL-PASS-P" pkg)))
             (json-sym (and pkg (find-symbol "EPIC-CLOSURE-GATE-RESULT->JSON" pkg)))
             (res (and eval-sym (funcall eval-sym web-dir web-cmd tui-dir tui-cmd)))
             (ok (and res ok-sym (funcall ok-sym res))))
        (format t "~A~%" (if (and res json-sym)
                              (funcall json-sym res)
                              "{\"error\":\"closure-gate-symbols-missing\"}"))
        (unless ok
          (error "Epic 3/4 closure gate failed"))))
  (error (e)
    (format *error-output* "~&EPIC34 CLOSURE GATE ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
