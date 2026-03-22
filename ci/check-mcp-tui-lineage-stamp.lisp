;;; check-mcp-tui-lineage-stamp.lisp — deterministic T1-T6 lineage stamp verifier

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(let* ((root (or (uiop:getenv "TUI_EVIDENCE_DIR") "test-results/tui-regression-matrix/complete/"))
       (cmd (or (uiop:getenv "TUI_EVIDENCE_COMMAND") "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
       (stamp (orrery/adapter:evaluate-mcp-tui-lineage-stamp root cmd)))
  (format t "~A~%" (orrery/adapter:mcp-tui-lineage-stamp->json stamp))
  (uiop:quit (if (orrery/adapter:mtls-pass-p stamp) 0 1)))
