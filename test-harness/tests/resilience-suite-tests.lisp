;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; resilience-suite-tests.lisp — Tests for adapter resilience suite
;;; Bead: agent-orrery-eb0.7.2

(in-package #:orrery/harness-tests)

(define-test resilience-suite-tests

  (define-test default-scenarios-exist
    (let ((scenarios (orrery/adapter:make-default-resilience-scenarios)))
      (true (>= (length scenarios) 7))
      (true (find "R1-timeout-sessions" scenarios
                  :key #'orrery/adapter:fs-scenario-id :test #'string=))
      (true (find "R5-not-found-cron" scenarios
                  :key #'orrery/adapter:fs-scenario-id :test #'string=))))

  (define-test timeout-scenario-degrades
    (let* ((scenarios (orrery/adapter:make-default-resilience-scenarios))
           (r1 (find "R1-timeout-sessions" scenarios
                     :key #'orrery/adapter:fs-scenario-id :test #'string=))
           (result (orrery/adapter:run-resilience-scenario r1 :delegate (orrery/harness:make-fixture-adapter))))
      (true (orrery/adapter:rr-pass-p result))
      (is eq :degrade (orrery/adapter:rr-actual-recovery result))
      (true (orrery/adapter:rr-condition-caught-p result))))

  (define-test empty-response-skips
    (let* ((scenarios (orrery/adapter:make-default-resilience-scenarios))
           (r3 (find "R3-empty-events" scenarios
                     :key #'orrery/adapter:fs-scenario-id :test #'string=))
           (result (orrery/adapter:run-resilience-scenario r3 :delegate (orrery/harness:make-fixture-adapter))))
      (true (orrery/adapter:rr-pass-p result))
      (is eq :skip (orrery/adapter:rr-actual-recovery result))
      (false (orrery/adapter:rr-condition-caught-p result))))

  (define-test not-found-falls-back
    (let* ((scenarios (orrery/adapter:make-default-resilience-scenarios))
           (r5 (find "R5-not-found-cron" scenarios
                     :key #'orrery/adapter:fs-scenario-id :test #'string=))
           (result (orrery/adapter:run-resilience-scenario r5 :delegate (orrery/harness:make-fixture-adapter))))
      (true (orrery/adapter:rr-pass-p result))
      (is eq :fallback (orrery/adapter:rr-actual-recovery result))
      (true (orrery/adapter:rr-condition-caught-p result))))

  (define-test not-supported-skips
    (let* ((scenarios (orrery/adapter:make-default-resilience-scenarios))
           (r6 (find "R6-not-supported-alerts" scenarios
                     :key #'orrery/adapter:fs-scenario-id :test #'string=))
           (result (orrery/adapter:run-resilience-scenario r6 :delegate (orrery/harness:make-fixture-adapter))))
      (true (orrery/adapter:rr-pass-p result))
      (is eq :skip (orrery/adapter:rr-actual-recovery result))))

  (define-test full-suite-passes
    (let ((report (orrery/adapter:run-resilience-suite
                   (orrery/adapter:make-default-resilience-scenarios)
                   :timestamp 5000
                   :delegate (orrery/harness:make-fixture-adapter))))
      (true (orrery/adapter:rrep-pass-p report))
      (is = 7 (orrery/adapter:rrep-total report))
      (is = 7 (orrery/adapter:rrep-passed report))
      (is = 0 (orrery/adapter:rrep-failed report))))

  (define-test report-json-shape
    (let* ((report (orrery/adapter:run-resilience-suite
                    (orrery/adapter:make-default-resilience-scenarios)
                    :timestamp 6000
                    :delegate (orrery/harness:make-fixture-adapter)))
           (json (orrery/adapter:resilience-report->json report)))
      (true (search "\"pass\":true" json))
      (true (search "\"total\":7" json))
      (true (search "\"results\"" json))
      (true (search "R1-timeout-sessions" json)))))
