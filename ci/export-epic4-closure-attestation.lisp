;;; ci/export-epic4-closure-attestation.lisp — Epic 4 closure attestation exporter CI gate
;;; Usage: sbcl --script ci/export-epic4-closure-attestation.lisp

(require :asdf)
(let ((home-ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file home-ql) (load home-ql)))
(pushnew #P"/home/slime/projects/agent-orrery/" asdf:*central-registry* :test #'equal)

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((artifact-root "test-results/playwright-artifacts/")
             (output-path "test-results/epic4-closure-attestation.json"))
        (ensure-directories-exist output-path)
        (funcall (find-symbol "RUN-EPIC4-CLOSURE-ATTESTATION-EXPORTER" :orrery/adapter)
                 artifact-root output-path)))
  (error (e)
    (format *error-output* "~&ERROR: ~A~%" e)
    (sb-ext:exit :code 1)))
