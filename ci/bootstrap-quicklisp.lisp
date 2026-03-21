;;; bootstrap-quicklisp.lisp — deterministic local quicklisp bootstrap for CI/workspace

(require :asdf)

(let* ((cwd (uiop:getcwd))
       (root (or (uiop:getenv "ORRERY_QL_ROOT")
                 (namestring (merge-pathnames "ci/.quicklisp/" (pathname cwd)))))
       (setup (merge-pathnames "setup.lisp" (pathname root)))
       (home-setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
       (quicklisp-loader "/tmp/quicklisp.lisp"))
  (ensure-directories-exist (merge-pathnames "dummy" (pathname root)))
  (unless (probe-file setup)
    (format t "~&[bootstrap] installing Quicklisp into ~A~%" root)
    (uiop:run-program (list "curl" "-fsSL" "https://beta.quicklisp.org/quicklisp.lisp" "-o" quicklisp-loader)
                      :output t :error-output t)
    (uiop:run-program
     (list "sbcl" "--noinform" "--non-interactive"
           "--load" quicklisp-loader
           "--eval" (format nil "(quicklisp-quickstart:install :path ~S)" root)
           "--eval" "(ignore-errors (ql-dist:install-dist \"http://beta.quicklisp.org/dist/quicklisp.txt\" :prompt nil))")
     :output t :error-output t))
  (cond ((probe-file setup)
         (load setup)
         (format t "~&[bootstrap] quicklisp ready: ~A~%" (namestring setup)))
        ((probe-file home-setup)
         (load home-setup)
         (format t "~&[bootstrap] fallback quicklisp ready: ~A~%" (namestring home-setup)))
        (t (error "Quicklisp bootstrap failed: no setup.lisp at ~A or ~A" setup home-setup))))

(sb-ext:exit :code 0)
