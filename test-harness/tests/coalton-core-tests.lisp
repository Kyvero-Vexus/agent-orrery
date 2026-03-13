;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; coalton-core-tests.lisp — Tests for Coalton pure-core baseline
;;;

(in-package #:orrery/harness-tests)

(define-test coalton-core-tests)

(define-test (coalton-core-tests normalize-status-code-mapping)
  (is string= "active" (normalize-status-code 0))
  (is string= "idle" (normalize-status-code 1))
  (is string= "closed" (normalize-status-code 2))
  (is string= "unknown" (normalize-status-code 999)))

(define-test (coalton-core-tests estimate-cost-cents-model)
  ;; ceil(tokens / 500)
  (is = 0 (estimate-cost-cents 0))
  (is = 1 (estimate-cost-cents 1))
  (is = 1 (estimate-cost-cents 500))
  (is = 2 (estimate-cost-cents 501))
  (is = 3 (estimate-cost-cents 1500))
  (is = 0 (estimate-cost-cents -1)))

(define-test (coalton-core-tests deterministic-results)
  (let ((inputs '(0 1 2 100 499 500 501 5000)))
    (dolist (x inputs)
      (is = (estimate-cost-cents x)
          (estimate-cost-cents x)))))
