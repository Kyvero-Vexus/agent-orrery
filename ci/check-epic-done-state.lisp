;;; check-epic-done-state.lisp — CI close-guard for Epic3/Epic4 done-state claims

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(defun parse-boolean (s)
  (not (null (member (string-downcase s) '("1" "true" "yes" "on") :test #'string=))))

(defun parse-epic-target (s)
  (let ((x (string-downcase s)))
    (cond ((string= x "epic3") :epic3)
          ((string= x "epic4") :epic4)
          (t :epic3))))

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((target (parse-epic-target (getenv-or "EPIC_TARGET" "epic3")))
             (done-claim (parse-boolean (getenv-or "DONE_CLAIM" "true")))
             (artifacts (getenv-or "EVIDENCE_DIR"
                                   (if (eq target :epic4)
                                       "test-results/e2e-report/"
                                       "test-results/tui-artifacts/")))
             (command (getenv-or "EVIDENCE_COMMAND"
                                 (if (eq target :epic4)
                                     "cd e2e && ./run-e2e.sh"
                                     "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (web-dir (getenv-or "WEB_EVIDENCE_DIR" "test-results/e2e-report/"))
             (web-cmd (getenv-or "WEB_EVIDENCE_COMMAND" "cd e2e && ./run-e2e.sh"))
             (tui-dir (getenv-or "TUI_EVIDENCE_DIR" "test-results/tui-artifacts/"))
             (tui-cmd (getenv-or "TUI_EVIDENCE_COMMAND" "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
             (pkg (find-package "ORRERY/ADAPTER"))
             (eval-sym (and pkg (find-symbol "EVALUATE-EPIC-DONE-STATE-GUARD" pkg)))
             (ok-sym (and pkg (find-symbol "EDR-ALLOWED-P" pkg)))
             (json-sym (and pkg (find-symbol "EPIC-DONE-STATE-RESULT->JSON" pkg)))
             (matrix-eval-sym (and pkg (find-symbol "EVALUATE-PROTOCOL-EVIDENCE-MATRIX" pkg)))
             (matrix-ok-sym (and pkg (find-symbol "PMREP-OVERALL-PASS-P" pkg)))
             (matrix-json-sym (and pkg (find-symbol "PROTOCOL-MATRIX-REPORT->JSON" pkg)))
             (gap-eval-sym (and pkg (find-symbol "EXPLAIN-PROTOCOL-EVIDENCE-GAPS" pkg)))
             (gap-ok-sym (and pkg (find-symbol "PEGR-CLOSURE-PASS-P" pkg)))
             (gap-json-sym (and pkg (find-symbol "PROTOCOL-EVIDENCE-GAP-REPORT->JSON" pkg)))
             (res (and eval-sym (funcall eval-sym target done-claim artifacts command)))
             (matrix-res (and matrix-eval-sym (funcall matrix-eval-sym web-dir web-cmd tui-dir tui-cmd)))
             (gap-res (and gap-eval-sym (funcall gap-eval-sym web-dir web-cmd tui-dir tui-cmd)))
             (ok (and res ok-sym (funcall ok-sym res)
                      matrix-res matrix-ok-sym (funcall matrix-ok-sym matrix-res)
                      gap-res gap-ok-sym (funcall gap-ok-sym gap-res))))
        (format t "~A~%" (if (and res json-sym)
                              (funcall json-sym res)
                              "{\"error\":\"done-state-guard-symbols-missing\"}"))
        (format t "~A~%" (if (and matrix-res matrix-json-sym)
                              (funcall matrix-json-sym matrix-res)
                              "{\"error\":\"protocol-matrix-symbols-missing\"}"))
        (format t "~A~%" (if (and gap-res gap-json-sym)
                              (funcall gap-json-sym gap-res)
                              "{\"error\":\"protocol-evidence-gap-symbols-missing\"}"))
        (unless ok
          (error "Epic done-state guard denied completion claim (or protocol matrix/evidence-gap denied)"))))
  (error (e)
    (format *error-output* "~&EPIC DONE-STATE GUARD ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
