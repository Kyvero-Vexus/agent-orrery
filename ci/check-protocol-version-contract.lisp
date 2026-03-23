;;; check-protocol-version-contract.lisp — Protocol version negotiation contract CLI
;;; Bead: agent-orrery-7mki
;;;
;;; Deterministic command:
;;;   sbcl --script ci/check-protocol-version-contract.lisp
;;;
;;; Exit codes:
;;;   0 - All version contracts compatible
;;;   1 - Compatibility mismatch

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((contract (orrery/adapter:compile-version-negotiation-contract))
       (json (orrery/adapter:version-negotiation-contract->json contract)))
  (format t "~A~%" json)
  (unless (orrery/adapter:vnc-all-compatible-p contract)
    (uiop:quit 1)))

(uiop:quit 0)
