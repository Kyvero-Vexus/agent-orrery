;;; check-epic3-evidence.lisp — explicit Epic 3 closure guard

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((pkg (find-package "ORRERY/ADAPTER"))
             (sym (and pkg (find-symbol "EPIC3-T1-T6-EVIDENCE-OK-P" pkg)))
             (ok (and sym (funcall sym "test-results/tui-artifacts/"))))
        (format t "~&Epic3 T1-T6 evidence guard: ~A~%" ok)
        (unless ok
          (error "Epic 3 T1-T6 evidence guard failed"))))
  (error (e)
    (format *error-output* "~&EPIC3 EVIDENCE GUARD ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
