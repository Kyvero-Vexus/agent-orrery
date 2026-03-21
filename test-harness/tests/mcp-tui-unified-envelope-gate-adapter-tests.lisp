(in-package #:orrery/harness-tests)

(define-test mcp-tui-unified-envelope-gate-adapter-suite)

(define-test (mcp-tui-unified-envelope-gate-adapter-suite pass-complete)
  (let ((dir (%mk-temp-envelope-dir "gate-ok")))
    (unwind-protect
         (progn
           (%seed-complete-envelope-artifacts dir)
           (let ((res (orrery/adapter:evaluate-mcp-tui-unified-envelope-gate-adapter
                       dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:mtgar-pass-p res))
             (true (search "\"blocking\":false" (orrery/adapter:mcp-tui-gate-adapter-result->json res)))))
      (%cleanup-envelope-dir dir))))

(define-test (mcp-tui-unified-envelope-gate-adapter-suite fail-on-command-drift)
  (let ((dir (%mk-temp-envelope-dir "gate-drift")))
    (unwind-protect
         (progn
           (%seed-complete-envelope-artifacts dir)
           (let ((res (orrery/adapter:evaluate-mcp-tui-unified-envelope-gate-adapter dir "make e2e-tui")))
             (false (orrery/adapter:mtgar-pass-p res))
             (true (search "command-drift" (orrery/adapter:mcp-tui-gate-adapter-result->json res)))))
      (%cleanup-envelope-dir dir))))
