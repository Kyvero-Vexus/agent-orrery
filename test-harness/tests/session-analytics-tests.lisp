;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; session-analytics-tests.lisp — Tests for Coalton session analytics
;;; Bead: agent-orrery-3jv

(in-package #:orrery/harness-tests)

(define-test session-analytics-suite

  (define-test single-session-efficiency
    (let* ((m (orrery/coalton/core:cl-make-session-metric "s1" 600 3000 30 150 "gpt-4"))
           (e (orrery/coalton/core:cl-compute-efficiency m)))
      (is string= "s1" (orrery/coalton/core:cl-em-id e))
      (is = 100 (orrery/coalton/core:cl-em-tokens-per-message e))
      (is = 300 (orrery/coalton/core:cl-em-tokens-per-minute e))
      (is = 50 (orrery/coalton/core:cl-em-cost-per-1k e))))

  (define-test short-session-efficiency
    (let* ((m (orrery/coalton/core:cl-make-session-metric "s2" 30 500 5 25 "claude-3"))
           (e (orrery/coalton/core:cl-compute-efficiency m)))
      (is = 100 (orrery/coalton/core:cl-em-tokens-per-message e))))

  (define-test aggregate-three-sessions
    (let* ((metrics (list
                     (orrery/coalton/core:cl-make-session-metric "a" 120 2000 20 100 "gpt-4")
                     (orrery/coalton/core:cl-make-session-metric "b" 600 6000 60 300 "gpt-4")
                     (orrery/coalton/core:cl-make-session-metric "c" 3600 12000 120 600 "claude-3")))
           (summary (orrery/coalton/core:cl-analyze-sessions metrics)))
      (is = 3 (orrery/coalton/core:cl-sas-total summary))
      (is = 1440 (orrery/coalton/core:cl-sas-avg-duration summary))
      (is = 1000 (orrery/coalton/core:cl-sas-total-cost summary))
      (is = 100 (orrery/coalton/core:cl-sas-avg-tokens-per-msg summary))))

  (define-test duration-distribution
    (let* ((metrics (list
                     (orrery/coalton/core:cl-make-session-metric "a" 30  1000 10 50 "m")
                     (orrery/coalton/core:cl-make-session-metric "b" 45  1000 10 50 "m")
                     (orrery/coalton/core:cl-make-session-metric "c" 120 2000 20 100 "m")
                     (orrery/coalton/core:cl-make-session-metric "d" 600 3000 30 150 "m")
                     (orrery/coalton/core:cl-make-session-metric "e" 7200 10000 100 500 "m")))
           (summary (orrery/coalton/core:cl-analyze-sessions metrics))
           (buckets (orrery/coalton/core:cl-sas-duration-buckets summary)))
      (is = 5 (length buckets))
      ;; First bucket: <1min — sessions a, b
      (is string= "<1min" (orrery/coalton/core:cl-db-label (first buckets)))
      (is = 2 (orrery/coalton/core:cl-db-count (first buckets)))
      ;; Second bucket: 1-5min — session c
      (is string= "1-5min" (orrery/coalton/core:cl-db-label (second buckets)))
      (is = 1 (orrery/coalton/core:cl-db-count (second buckets)))))

  (define-test efficiency-list-matches-input
    (let* ((metrics (list
                     (orrery/coalton/core:cl-make-session-metric "a" 600 3000 30 150 "m")
                     (orrery/coalton/core:cl-make-session-metric "b" 300 1500 15 75 "m")))
           (summary (orrery/coalton/core:cl-analyze-sessions metrics))
           (effs (orrery/coalton/core:cl-sas-efficiency summary)))
      (is = 2 (length effs))))

  (define-test zero-messages-safe
    (let* ((m (orrery/coalton/core:cl-make-session-metric "z" 600 0 0 0 "m"))
           (e (orrery/coalton/core:cl-compute-efficiency m)))
      (is = 0 (orrery/coalton/core:cl-em-tokens-per-message e))
      (is = 0 (orrery/coalton/core:cl-em-tokens-per-minute e)))))
