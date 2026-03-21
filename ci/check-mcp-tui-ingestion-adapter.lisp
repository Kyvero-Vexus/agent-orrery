;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(require :asdf)

(let* ((local-ql (merge-pathnames "setup.lisp" (pathname "ci/.quicklisp/")))
       (home-ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (cond ((probe-file local-ql) (load local-ql))
        ((probe-file home-ql) (load home-ql))
        (t (format *error-output* "~&LOAD ERROR: Quicklisp setup not found. Run: sbcl --script ci/bootstrap-quicklisp.lisp~%")
           (sb-ext:exit :code 2))))

(dolist (path (list #P"/home/slime/projects/agent-orrery/"
                    (truename ".")))
  (pushnew path asdf:*central-registry* :test #'equal))

(asdf:clear-source-registry)
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "TUI_ARTIFACTS_DIR") "test-results/tui-artifacts"))
       (cmd (or (uiop:getenv "TUI_COMMAND") "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
       (result (orrery/adapter:evaluate-mcp-tui-ingestion-adapter root cmd)))
  (format t "~A~%" (orrery/adapter:mcp-tui-ingestion-result->json result))
  (unless (orrery/adapter:mtir-pass-p result)
    (sb-ext:exit :code 1)))
