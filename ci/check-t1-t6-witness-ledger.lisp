;;; check-t1-t6-witness-ledger.lisp — T1-T6 artifact witness ledger + lockfile emitter CLI
;;; Bead: agent-orrery-om6o
;;;
;;; Deterministic command:
;;;   sbcl --script ci/check-t1-t6-witness-ledger.lisp
;;;
;;; Exit codes:
;;;   0 - All T1-T6 artifacts witnessed (CLOSED)
;;;   1 - Missing artifacts (OPEN)

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((artifact-root "test-results/")
       (command       "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")
       (matrix        (orrery/adapter:compile-tui-contract-matrix artifact-root command))
       (ledger        (orrery/adapter:compile-t1-t6-witness-ledger matrix artifact-root))
       (json          (orrery/adapter:t1-t6-witness-ledger->json ledger)))
  (format t "~A~%" json)
  (unless (orrery/adapter:twl-all-present-p ledger)
    (uiop:quit 1)))

(uiop:quit 0)
