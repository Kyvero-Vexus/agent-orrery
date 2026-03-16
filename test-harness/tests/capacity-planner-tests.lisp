;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capacity-planner-tests.lisp — Tests for Coalton capacity planner
;;; Bead: agent-orrery-j9c

(in-package #:orrery/harness-tests)

(define-test capacity-planner-suite

  (define-test zone-idle
    (let* ((spec (orrery/coalton/core:cl-make-threshold-spec "sessions" 500 800 1000))
           (assess (orrery/coalton/core:cl-evaluate-threshold 100 spec)))
      (is string= "idle" (orrery/coalton/core:cl-assess-zone-label assess))
      (is = 400 (orrery/coalton/core:cl-assess-headroom assess))))

  (define-test zone-normal
    (let* ((spec (orrery/coalton/core:cl-make-threshold-spec "sessions" 500 800 1000))
           (assess (orrery/coalton/core:cl-evaluate-threshold 300 spec)))
      (is string= "normal" (orrery/coalton/core:cl-assess-zone-label assess))))

  (define-test zone-caution
    (let* ((spec (orrery/coalton/core:cl-make-threshold-spec "sessions" 500 800 1000))
           (assess (orrery/coalton/core:cl-evaluate-threshold 600 spec)))
      (is string= "caution" (orrery/coalton/core:cl-assess-zone-label assess))
      (is = 200 (orrery/coalton/core:cl-assess-headroom assess))))

  (define-test zone-critical
    (let* ((spec (orrery/coalton/core:cl-make-threshold-spec "sessions" 500 800 1000))
           (assess (orrery/coalton/core:cl-evaluate-threshold 900 spec)))
      (is string= "critical" (orrery/coalton/core:cl-assess-zone-label assess))
      (is = 100 (orrery/coalton/core:cl-assess-headroom assess))))

  (define-test zone-overflow
    (let* ((spec (orrery/coalton/core:cl-make-threshold-spec "sessions" 500 800 1000))
           (assess (orrery/coalton/core:cl-evaluate-threshold 1200 spec)))
      (is string= "overflow" (orrery/coalton/core:cl-assess-zone-label assess))
      (is = 0 (orrery/coalton/core:cl-assess-headroom assess))))

  (define-test utilization-pct
    (let* ((spec (orrery/coalton/core:cl-make-threshold-spec "tokens" 50000 80000 100000))
           (assess (orrery/coalton/core:cl-evaluate-threshold 75000 spec)))
      (is = 75 (orrery/coalton/core:cl-assess-util-pct assess))))

  (define-test default-thresholds-exist
    (let ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds)))
      (is = 4 (length thresholds))))

  (define-test full-plan-normal
    (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
           (values (list 100 20000 2000 50))
           (plan (orrery/coalton/core:cl-build-capacity-plan thresholds values)))
      (is string= "normal" (orrery/coalton/core:cl-plan-worst-zone-label plan))
      (true (> (orrery/coalton/core:cl-plan-headroom-pct plan) 0))
      (is = 4 (length (orrery/coalton/core:cl-plan-assessments plan)))))

  (define-test full-plan-critical
    (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
           (values (list 900 90000 9000 250))
           (plan (orrery/coalton/core:cl-build-capacity-plan thresholds values)))
      (is string= "critical" (orrery/coalton/core:cl-plan-worst-zone-label plan))))

  (define-test recommendation-text
    (let* ((spec (orrery/coalton/core:cl-make-threshold-spec "test" 10 20 30))
           (assess (orrery/coalton/core:cl-evaluate-threshold 25 spec)))
      (true (search "Scale up" (orrery/coalton/core:cl-assess-recommendation assess))))))
