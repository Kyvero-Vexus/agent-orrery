;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cost-optimizer-tests.lisp — Tests for Coalton cost-optimizer
;;; Bead: agent-orrery-nhh

(in-package #:orrery/harness-tests)

(define-test cost-optimizer-suite

  ;; Helper: make test profiles
  (define-test cost-opt-profiles-exist
    (let ((cheap (orrery/coalton/core:cl-make-model-cost-profile "cheap" 10 20 600 300))
          (quality (orrery/coalton/core:cl-make-model-cost-profile "quality" 100 200 950 500)))
      (true (not (null cheap)))
      (true (not (null quality)))))

  ;; Helper: make usage entries
  (define-test cost-opt-recommend-cost
    (let* ((cheap (orrery/coalton/core:cl-make-model-cost-profile "cheap" 10 20 600 300))
           (quality (orrery/coalton/core:cl-make-model-cost-profile "quality" 100 200 950 500))
           (profiles (list cheap quality))
           (entries (loop for i from 1 to 50
                          collect (orrery/coalton/core:cl-make-usage-entry
                                   "quality" (* i 100) (* i 50) i)))
           (rec (orrery/coalton/core:cl-recommend-model profiles entries (orrery/coalton/core:cl-opt-cost))))
      (is string= "cheap" (orrery/coalton/core:cl-rr-model rec))
      (is string= "cost" (orrery/coalton/core:cl-rr-strategy-label rec))))

  (define-test cost-opt-recommend-quality
    (let* ((cheap (orrery/coalton/core:cl-make-model-cost-profile "cheap" 10 20 600 300))
           (quality (orrery/coalton/core:cl-make-model-cost-profile "premium" 100 200 950 500))
           (profiles (list cheap quality))
           (entries (loop for i from 1 to 30
                          collect (orrery/coalton/core:cl-make-usage-entry
                                   "cheap" (* i 100) (* i 50) i)))
           (rec (orrery/coalton/core:cl-recommend-model profiles entries (orrery/coalton/core:cl-opt-quality))))
      (is string= "premium" (orrery/coalton/core:cl-rr-model rec))
      (is string= "quality" (orrery/coalton/core:cl-rr-strategy-label rec))))

  (define-test cost-opt-recommend-latency
    (let* ((fast (orrery/coalton/core:cl-make-model-cost-profile "fast" 50 100 700 100))
           (slow (orrery/coalton/core:cl-make-model-cost-profile "slow" 30 60 800 800))
           (profiles (list fast slow))
           (entries (loop for i from 1 to 10
                          collect (orrery/coalton/core:cl-make-usage-entry
                                   "slow" 1000 500 i)))
           (rec (orrery/coalton/core:cl-recommend-model profiles entries (orrery/coalton/core:cl-opt-latency))))
      (is string= "fast" (orrery/coalton/core:cl-rr-model rec))
      (is string= "latency" (orrery/coalton/core:cl-rr-strategy-label rec))))

  (define-test cost-opt-confidence-low
    (let* ((m (orrery/coalton/core:cl-make-model-cost-profile "m" 10 20 700 300))
           (profiles (list m))
           (entries (loop for i from 1 to 5
                          collect (orrery/coalton/core:cl-make-usage-entry "m" 100 50 i)))
           (rec (orrery/coalton/core:cl-recommend-model profiles entries (orrery/coalton/core:cl-opt-cost))))
      (is string= "low" (orrery/coalton/core:cl-rr-confidence-label rec))))

  (define-test cost-opt-confidence-high
    (let* ((m (orrery/coalton/core:cl-make-model-cost-profile "m" 10 20 700 300))
           (profiles (list m))
           (entries (loop for i from 1 to 150
                          collect (orrery/coalton/core:cl-make-usage-entry "m" 100 50 i)))
           (rec (orrery/coalton/core:cl-recommend-model profiles entries (orrery/coalton/core:cl-opt-cost))))
      (is string= "high" (orrery/coalton/core:cl-rr-confidence-label rec))))

  (define-test cost-opt-analyze-returns-analysis
    (let* ((cheap (orrery/coalton/core:cl-make-model-cost-profile "cheap" 10 20 600 300))
           (profiles (list cheap))
           (entries (loop for i from 1 to 50
                          collect (orrery/coalton/core:cl-make-usage-entry "cheap" 1000 500 i)))
           (analysis (orrery/coalton/core:cl-analyze-cost profiles entries (orrery/coalton/core:cl-opt-cost))))
      (true (>= (orrery/coalton/core:cl-ca-current-cost analysis) 0))
      (true (>= (orrery/coalton/core:cl-ca-optimal-cost analysis) 0))
      (is string= "cost" (orrery/coalton/core:cl-ca-strategy-label analysis))))

  (define-test cost-opt-strategy-labels
    (is string= "cost" (orrery/coalton/core:cl-rr-strategy-label
                         (let* ((m (orrery/coalton/core:cl-make-model-cost-profile "m" 10 20 700 300))
                                (entries (list (orrery/coalton/core:cl-make-usage-entry "m" 100 50 1))))
                           (orrery/coalton/core:cl-recommend-model (list m) entries (orrery/coalton/core:cl-opt-cost)))))
    (is string= "balanced" (orrery/coalton/core:cl-rr-strategy-label
                              (let* ((m (orrery/coalton/core:cl-make-model-cost-profile "m" 10 20 700 300))
                                     (entries (list (orrery/coalton/core:cl-make-usage-entry "m" 100 50 1))))
                                (orrery/coalton/core:cl-recommend-model (list m) entries (orrery/coalton/core:cl-opt-balanced)))))))
