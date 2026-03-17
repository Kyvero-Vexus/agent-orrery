;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; adapter-contract-checker-tests.lisp — Tests for typed adapter contract checker
;;; Beads: agent-orrery-doy, agent-orrery-5ue, agent-orrery-chx

(in-package #:orrery/harness-tests)

(define-test adapter-contract-checker-suite)

(define-test (adapter-contract-checker-suite default-cases-pass)
  (let ((report (orrery/adapter:run-adapter-contract-checker
                 (orrery/adapter:make-default-adapter-contract-cases))))
    (true (orrery/adapter:acp-pass-p report))
    (is = 0 (orrery/adapter:acp-failed report))
    (true (search "\"pass\":true" (orrery/adapter:adapter-contract-report->json report)))))

(define-test (adapter-contract-checker-suite mismatch-fails)
  (let* ((bad (list (orrery/adapter:make-adapter-contract-case
                    :surface :web
                    :kind :session
                    :payload (list (cons :session-id "s") (cons :agent "a") (cons :model 123) (cons :status :active))
                    :source "bad")))
         (report (orrery/adapter:run-adapter-contract-checker bad))
         (row (first (orrery/adapter:acp-rows report))))
    (false (orrery/adapter:acp-pass-p report))
    (is = 1 (orrery/adapter:acp-failed report))
    (true (> (length (orrery/adapter:acr-remediation-hints row)) 0))
    (true (> (length (orrery/adapter:acp-grouped-failures report)) 0))))

(define-test (adapter-contract-checker-suite fixture-pass)
  (let ((report (orrery/adapter:run-adapter-contract-checker-from-fixture
                 "test-harness/fixtures/adapter-replay-fixtures.lisp")))
    (true (orrery/adapter:acp-pass-p report))
    (is = 7 (length (orrery/adapter:acp-rows report)))
    ;; Expanded corpus includes cost/capacity/audit/analytics payload kinds.
    (true (find :cost (orrery/adapter:acp-rows report) :key #'orrery/adapter:acr-kind :test #'eq))
    (true (find :capacity (orrery/adapter:acp-rows report) :key #'orrery/adapter:acr-kind :test #'eq))
    (true (find :audit (orrery/adapter:acp-rows report) :key #'orrery/adapter:acr-kind :test #'eq))))
