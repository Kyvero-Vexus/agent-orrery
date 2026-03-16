;;; Start the Orrery web server for E2E testing
(load "/home/slime/quicklisp/setup.lisp")
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (ql:quickload :agent-orrery :silent t))
(orrery/web:start-server :port 7890)
(format t "~&Server ready on port 7890~%")
(force-output)
;; Keep running
(loop (sleep 1))
