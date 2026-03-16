;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; configuration-tests.lisp — Tests for typed Coalton configuration schema
;;; Bead: agent-orrery-1oe

(in-package #:orrery/harness-tests)

(define-test configuration-suite

  (define-test default-config-valid
    (let ((cfg (orrery/coalton/core:cl-default-runtime-config)))
      (true (orrery/coalton/core:cl-config-valid-p cfg))
      (is = 0 (orrery/coalton/core:cl-config-error-count cfg))
      (is string= "http://localhost" (orrery/coalton/core:cl-config-host cfg))
      (is = 7474 (orrery/coalton/core:cl-config-port cfg))
      (is string= "dark" (orrery/coalton/core:cl-config-theme cfg))))

  (define-test invalid-config-error-reporting
    (let ((cfg (orrery/coalton/core:cl-make-runtime-config
                "" 0 ""
                "neon" 0 nil
                0 0 0
                t t t)))
      (false (orrery/coalton/core:cl-config-valid-p cfg))
      (true (> (orrery/coalton/core:cl-config-error-count cfg) 0))
      (true (plusp (length (orrery/coalton/core:cl-config-first-error cfg))))))

  (define-test budget-threshold-order-validation
    (let ((cfg (orrery/coalton/core:cl-make-runtime-config
                "http://x" 8080 ""
                "light" 3 t
                5 1000 500
                t t t)))
      (false (orrery/coalton/core:cl-config-valid-p cfg))
      (true (search "budget-critical-cents" (orrery/coalton/core:cl-config-first-error cfg)))))

  (define-test merge-config-overrides
    (let* ((base (orrery/coalton/core:cl-default-runtime-config))
           (override (orrery/coalton/core:cl-make-runtime-config
                      "http://prod" 9000 "tok"
                      "light" 2 t
                      15 400 1600
                      t nil t))
           (merged (orrery/coalton/core:cl-merge-runtime-config base override)))
      (is string= "http://prod" (orrery/coalton/core:cl-config-host merged))
      (is = 9000 (orrery/coalton/core:cl-config-port merged))
      (is string= "light" (orrery/coalton/core:cl-config-theme merged))
      (is = 15 (orrery/coalton/core:cl-config-polling-seconds merged))
      (is = 400 (orrery/coalton/core:cl-config-budget-warning-cents merged))
      (is = 1600 (orrery/coalton/core:cl-config-budget-critical-cents merged))
      (true (orrery/coalton/core:cl-config-web-enabled-p merged))
      (false (orrery/coalton/core:cl-config-tui-enabled-p merged))
      (true (orrery/coalton/core:cl-config-mcclim-enabled-p merged))))

  (define-test merge-positive-default-retention
    (let* ((base (orrery/coalton/core:cl-default-runtime-config))
           (override (orrery/coalton/core:cl-make-runtime-config
                      "" 0 ""
                      "" 0 nil
                      0 0 0
                      t t t))
           (merged (orrery/coalton/core:cl-merge-runtime-config base override)))
      (is string= "http://localhost" (orrery/coalton/core:cl-config-host merged))
      (is = 7474 (orrery/coalton/core:cl-config-port merged))
      (is = 5 (orrery/coalton/core:cl-config-polling-seconds merged)))))
