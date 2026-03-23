;;; check-playwright-hook-preflight.lisp — Playwright S1-S6 verifier-hook adapter + JSON preflight CLI
;;; Bead: agent-orrery-3j2
;;;
;;; Deterministic command:
;;;   sbcl --script ci/check-playwright-hook-preflight.lisp
;;;
;;; Exit codes:
;;;   0 - All S1-S6 preflight hooks pass (CLOSED)
;;;   1 - Preflight failure (OPEN)

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((artifact-root "test-results/e2e-artifacts/")
       (command       "cd e2e && bash run-e2e.sh")
       (table         (orrery/adapter:compile-playwright-replay-table artifact-root command))
       (verdict       (orrery/adapter:run-playwright-s1-s6-hook-preflight table))
       (json          (orrery/adapter:playwright-hook-verdict->json verdict)))
  (format t "~A~%" json)
  (unless (orrery/adapter:phv-pass-p verdict)
    (uiop:quit 1)))

(uiop:quit 0)
