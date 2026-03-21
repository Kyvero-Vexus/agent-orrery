;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-witness-verifier-suite)

(define-test (mcp-tui-witness-verifier-suite pass-on-valid-bundle)
  (let ((dir (%mk-temp-witness-dir "verify-ok")))
    (unwind-protect
         (progn
           (%seed-witness-artifacts dir)
           (let* ((cmd "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")
                  (bundle (orrery/adapter:evaluate-mcp-tui-witness-bundle dir cmd))
                  (verification (orrery/adapter:verify-mcp-tui-witness-bundle bundle cmd)))
             (true (orrery/adapter:mtwv-pass-p verification))
             (true (orrery/adapter:mtwv-signature-valid-p verification))
             (true (orrery/adapter:mtwv-command-lineage-valid-p verification))
             (true (orrery/adapter:mtwv-digest-map-valid-p verification))))
      (%cleanup-witness-dir dir))))

(define-test (mcp-tui-witness-verifier-suite fail-on-signature-tamper)
  (let ((dir (%mk-temp-witness-dir "verify-bad-sig")))
    (unwind-protect
         (progn
           (%seed-witness-artifacts dir)
           (let* ((cmd "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")
                  (bundle (orrery/adapter:evaluate-mcp-tui-witness-bundle dir cmd)))
             (setf (orrery/adapter:mtwb-signature bundle) "witness-tampered")
             (let ((verification (orrery/adapter:verify-mcp-tui-witness-bundle bundle cmd)))
               (false (orrery/adapter:mtwv-pass-p verification))
               (false (orrery/adapter:mtwv-signature-valid-p verification)))))
      (%cleanup-witness-dir dir))))
