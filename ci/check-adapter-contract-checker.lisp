;;; check-adapter-contract-checker.lisp — CI gate for typed adapter contract checker

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((fixture (getenv-or "ADAPTER_FIXTURE" "test-harness/fixtures/adapter-replay-fixtures.lisp"))
             (pkg (find-package "ORRERY/ADAPTER"))
             (run-sym (and pkg (find-symbol "RUN-ADAPTER-CONTRACT-CHECKER-FROM-FIXTURE" pkg)))
             (ok-sym (and pkg (find-symbol "ACP-PASS-P" pkg)))
             (json-sym (and pkg (find-symbol "ADAPTER-CONTRACT-REPORT->JSON" pkg)))
             (res (and run-sym (funcall run-sym fixture)))
             (ok (and res ok-sym (funcall ok-sym res))))
        (format t "~A~%" (if (and res json-sym)
                              (funcall json-sym res)
                              "{\"error\":\"adapter-checker-symbols-missing\"}"))
        (unless ok
          (error "Adapter contract checker gate failed"))))
  (error (e)
    (format *error-output* "~&ADAPTER CONTRACT CHECKER ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
