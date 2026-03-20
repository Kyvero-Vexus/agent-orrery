(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let ((pack (orrery/adapter:build-mcp-tui-command-pack)))
  (format t "~A~%" (orrery/adapter:mcp-tui-command-pack->json pack))
  (unless (orrery/adapter:mtcp-pass-p pack)
    (uiop:quit 1)))

(uiop:quit 0)
