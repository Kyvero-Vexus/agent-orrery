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
             (pkg (find-package "ORRERY/ADAPTER"))
             (eval-sym (and pkg (find-symbol "EVALUATE-EPIC-DONE-STATE-GUARD" pkg)))
             (ok-sym (and pkg (find-symbol "EDR-ALLOWED-P" pkg)))
             (json-sym (and pkg (find-symbol "EPIC-DONE-STATE-RESULT->JSON" pkg)))
             (res (and eval-sym (funcall eval-sym target done-claim artifacts command)))
             (ok (and res ok-sym (funcall ok-sym res))))
        (format t "~A~%" (if (and res json-sym)
                              (funcall json-sym res)
                              "{\"error\":\"done-state-guard-symbols-missing\"}"))
        (unless ok
          (error "Epic done-state guard denied completion claim"))))
  (error (e)
    (format *error-output* "~&EPIC DONE-STATE GUARD ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
