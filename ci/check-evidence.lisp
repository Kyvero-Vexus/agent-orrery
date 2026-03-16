;;; check-evidence.lisp — CI evidence gate for web/tui E2E artifacts

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (multiple-value-bind (web-ok tui-ok)
          (orrery/adapter:ci-check-all-evidence)
        (format t "~&WEB evidence: ~A~%TUI evidence: ~A~%" web-ok tui-ok)
        (unless (and web-ok tui-ok)
          (error "Evidence gate failed"))))
  (error (e)
    (format *error-output* "~&EVIDENCE GATE ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
