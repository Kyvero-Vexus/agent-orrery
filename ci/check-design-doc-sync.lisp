;;; check-design-doc-sync.lisp — validate design-doc sync for a bead
;;;
;;; Usage:
;;;   BEAD_ID=agent-orrery-xyz \
;;;   BEAD_TITLE='...' \
;;;   BEAD_DESCRIPTION='...Mandatory: develop/update Common Lisp design docs in /home/slime/projects/emacsen-design-docs...' \
;;;   DOCS_ROOT=/home/slime/projects/emacsen-design-docs/agent-orrery \
;;;   ARTIFACTS_ROOT=test-results/ \
;;;   sbcl --script ci/check-design-doc-sync.lisp

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((bead-id (getenv-or "BEAD_ID" ""))
             (title (getenv-or "BEAD_TITLE" ""))
             (description (getenv-or "BEAD_DESCRIPTION" ""))
             (docs-root (getenv-or "DOCS_ROOT" "/home/slime/projects/emacsen-design-docs/agent-orrery/"))
             (artifacts-root (getenv-or "ARTIFACTS_ROOT" "test-results/"))
             (pkg (find-package "ORRERY/ADAPTER"))
             (eval-sym (and pkg (find-symbol "EVALUATE-BEAD-ACCEPTANCE" pkg)))
             (ok-sym (and pkg (find-symbol "BAR-OVERALL-OK-P" pkg)))
             (json-sym (and pkg (find-symbol "BEAD-ACCEPTANCE-RESULT->JSON" pkg)))
             (res (and eval-sym (funcall eval-sym bead-id title description docs-root artifacts-root)))
             (ok (and res ok-sym (funcall ok-sym res))))
        (format t "~A~%" (if (and res json-sym)
                              (funcall json-sym res)
                              "{\"error\":\"checker-symbols-missing\"}"))
        (unless ok
          (error "Design-doc sync check failed"))))
  (error (e)
    (format *error-output* "~&DESIGN DOC SYNC CHECK ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
