;;; unified-closure-gate-cli-tests.lisp

(in-package #:orrery/harness-tests)

(define-test unified-closure-gate-cli-suite)

(define-test (unified-closure-gate-cli-suite emits-acceptance-artifact-with-gate-adapter)
  (let* ((out "/tmp/orrery-unified-closure-acceptance.json")
         (cmd (format nil "WEB_EVIDENCE_DIR=test-results/e2e-regression-matrix/complete/ TUI_EVIDENCE_DIR=test-results/tui-regression-matrix/complete/ UNIFIED_CLOSURE_OUT=~A /home/slime/.guix-profile/bin/sbcl --eval '(load \"/home/slime/quicklisp/setup.lisp\")' --script ci/check-unified-closure-gate.lisp" out)))
    (uiop:run-program cmd :ignore-error-status t :output :string :error-output :string)
    (true (probe-file out))
    (let* ((txt (with-open-file (s out :direction :input)
                  (let ((buf (make-string (file-length s))))
                    (read-sequence buf s)
                    buf))))
      (true (search "\"deterministic_verification_command\":" txt))
      (true (search "\"gate_adapter\":" txt))
      (true (search "\"command_hash\":" txt))
      (true (search "\"missing_scenarios\":" txt)))))
