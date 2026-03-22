;;; ci/validate-t1-t6-evidence.lisp — CI gate: T1-T6 evidence validator
;;; Bead: agent-orrery-1ts
;;;
;;; Usage:
;;;   sbcl --script ci/validate-t1-t6-evidence.lisp \
;;;     --tui-evidence-dir test-results/tui-artifacts/ \
;;;     --tui-command "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
;;;
;;; Exit 0 = all T1-T6 evidence validates; Exit 1 = gate failure.

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((args (uiop:command-line-arguments))
       (dir-pos (position "--tui-evidence-dir" args :test #'string=))
       (cmd-pos (position "--tui-command" args :test #'string=))
       (dir (if dir-pos (nth (1+ dir-pos) args)
                (or (uiop:getenv "TUI_EVIDENCE_DIR") "test-results/tui-artifacts/")))
       (cmd (if cmd-pos (nth (1+ cmd-pos) args)
                (or (uiop:getenv "TUI_EVIDENCE_COMMAND")
                    "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
       (verdict (orrery/adapter:evaluate-t1t6-evidence-validator dir cmd))
       (json    (orrery/adapter:t1t6-closure-verdict->json verdict)))
  (format t "~A~%" json)
  (unless (orrery/adapter:t1t6cv-pass-p verdict)
    (format *error-output*
            "FAIL: T1-T6 evidence validation failed: ~A~%"
            (orrery/adapter:t1t6cv-detail verdict))
    (uiop:quit 1)))

(uiop:quit 0)
