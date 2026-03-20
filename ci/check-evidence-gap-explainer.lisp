;;; check-evidence-gap-explainer.lisp — deterministic CLI wrapper + artifact output contract

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
             (out (getenv-or "EVIDENCE_GAP_JSON" "test-results/evidence-gap/evidence-gap-report.json"))
             (pkg (find-package "ORRERY/ADAPTER"))
             (eval-sym (and pkg (find-symbol "EXPLAIN-PROTOCOL-EVIDENCE-GAPS" pkg)))
             (json-sym (and pkg (find-symbol "PROTOCOL-EVIDENCE-GAP-REPORT->JSON" pkg)))
             (pass-sym (and pkg (find-symbol "PEGR-CLOSURE-PASS-P" pkg)))
             (report (and eval-sym (funcall eval-sym web-dir web-cmd tui-dir tui-cmd)))
             (json (if (and report json-sym)
                       (funcall json-sym report)
                       "{\"error\":\"evidence-gap-symbols-missing\"}"))
             (ok (and report pass-sym (funcall pass-sym report))))
        (ensure-directories-exist out)
        (with-open-file (s out :direction :output :if-exists :supersede)
          (write-string json s))
        (format t "~A~%" json)
        (unless ok
          (error "Evidence gaps remain for Epic 3/4 closure"))))
  (error (e)
    (format *error-output* "~&EVIDENCE GAP EXPLAINER ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
