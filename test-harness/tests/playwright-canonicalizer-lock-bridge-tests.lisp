;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test playwright-canonicalizer-lock-bridge-suite)

(define-test (playwright-canonicalizer-lock-bridge-suite verdict-json-pass)
  (let ((v (orrery/adapter:make-lock-bridge-verdict
            :pass-p t
            :command "cd e2e && ./run-e2e.sh"
            :command-fp 12345
            :artifact-root "test-results/e2e-artifacts/"
            :complete-count 6
            :missing-scenarios nil
            :detail "canonical_pass=T command_ok=T missing="
            :timestamp 0)))
    (let ((json (orrery/adapter:lock-bridge-verdict->json v)))
      (true (search "\"pass\":true" json))
      (true (search "\"complete_count\":6" json))
      (true (search "\"missing\":[]" json)))))

(define-test (playwright-canonicalizer-lock-bridge-suite verdict-json-fail)
  (let ((v (orrery/adapter:make-lock-bridge-verdict
            :pass-p nil
            :command ""
            :command-fp 0
            :artifact-root ""
            :complete-count 4
            :missing-scenarios '("S3" "S5")
            :detail "canonical_pass=NIL command_ok=NIL missing=S3,S5"
            :timestamp 0)))
    (let ((json (orrery/adapter:lock-bridge-verdict->json v)))
      (true (search "\"pass\":false" json))
      (true (search "\"S3\"" json)))))
