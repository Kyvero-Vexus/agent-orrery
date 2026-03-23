;;; ci/compile-epic3-closure-dossier.lisp — Epic 3 closure dossier compiler CI gate
;;; Usage: sbcl --script ci/compile-epic3-closure-dossier.lisp

(require :asdf)
(let ((home-ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file home-ql) (load home-ql)))
(pushnew #P"/home/slime/projects/agent-orrery/" asdf:*central-registry* :test #'equal)

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((artifact-root "test-results/tui-artifacts/")
             (output-path "test-results/epic3-closure-dossier.json"))
        (ensure-directories-exist output-path)
        (funcall (find-symbol "RUN-EPIC3-CLOSURE-DOSSIER-COMPILER" :orrery/adapter)
                 artifact-root output-path)))
  (error (e)
    (format *error-output* "~&ERROR: ~A~%" e)
    (sb-ext:exit :code 1)))
