;;; check-protocol-evidence-matrix.lisp — CI gate for Epic11 protocol/evidence matrix

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
             (tui-cmd (getenv-or "TUI_EVIDENCE_COMMAND" "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
             (pkg (find-package "ORRERY/ADAPTER"))
             (eval-sym (and pkg (find-symbol "EVALUATE-PROTOCOL-EVIDENCE-MATRIX" pkg)))
             (ok-sym (and pkg (find-symbol "PMREP-OVERALL-PASS-P" pkg)))
             (json-sym (and pkg (find-symbol "PROTOCOL-MATRIX-REPORT->JSON" pkg)))
             (res (and eval-sym (funcall eval-sym web-dir web-cmd tui-dir tui-cmd)))
             (ok (and res ok-sym (funcall ok-sym res))))
        (format t "~A~%" (if (and res json-sym)
                              (funcall json-sym res)
                              "{\"error\":\"protocol-matrix-symbols-missing\"}"))
        (unless ok
          (error "Protocol/evidence matrix gate failed"))))
  (error (e)
    (format *error-output* "~&PROTOCOL EVIDENCE MATRIX ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
