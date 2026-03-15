;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
(in-package #:orrery/harness-tests)

(define-test budget-policy)

(define-test (budget-policy ok-threshold)
  (let* ((lim (orrery/coalton/core:cl-make-budget-limit :global nil :daily 1000 100))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list lim) 500)))
    (is = 1 (length verdicts))
    (is eq :ok (orrery/coalton/core:cl-verdict-level-keyword (first verdicts)))
    (is = 500 (orrery/coalton/core:cl-verdict-utilization (first verdicts)))))

(define-test (budget-policy warning-threshold)
  (let* ((lim (orrery/coalton/core:cl-make-budget-limit :global nil :daily 1000 100))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list lim) 750)))
    (is eq :warning (orrery/coalton/core:cl-verdict-level-keyword (first verdicts)))))

(define-test (budget-policy critical-threshold)
  (let* ((lim (orrery/coalton/core:cl-make-budget-limit :global nil :daily 1000 100))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list lim) 950)))
    (is eq :critical (orrery/coalton/core:cl-verdict-level-keyword (first verdicts)))))

(define-test (budget-policy exceeded-threshold)
  (let* ((lim (orrery/coalton/core:cl-make-budget-limit :global nil :daily 1000 100))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list lim) 1200)))
    (is eq :exceeded (orrery/coalton/core:cl-verdict-level-keyword (first verdicts)))
    (is = 1200 (orrery/coalton/core:cl-verdict-utilization (first verdicts)))))

(define-test (budget-policy zero-limit)
  (let* ((lim (orrery/coalton/core:cl-make-budget-limit :global nil :daily 0 0))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list lim) 100)))
    (is eq :exceeded (orrery/coalton/core:cl-verdict-level-keyword (first verdicts)))))

(define-test (budget-policy model-scope)
  (let* ((lim (orrery/coalton/core:cl-make-budget-limit :model "gpt-4" :monthly 5000 500))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list lim) 3000)))
    (is eq :ok (orrery/coalton/core:cl-verdict-level-keyword (first verdicts)))
    (is = 600 (orrery/coalton/core:cl-verdict-utilization (first verdicts)))))

(define-test (budget-policy multiple-limits)
  (let* ((l1 (orrery/coalton/core:cl-make-budget-limit :global nil :daily 1000 100))
         (l2 (orrery/coalton/core:cl-make-budget-limit :model "claude" :weekly 500 50))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list l1 l2) 600)))
    (is = 2 (length verdicts))
    (is eq :ok (orrery/coalton/core:cl-verdict-level-keyword (first verdicts)))
    (is eq :exceeded (orrery/coalton/core:cl-verdict-level-keyword (second verdicts)))))

(define-test (budget-policy hint-text)
  (let* ((lim (orrery/coalton/core:cl-make-budget-limit :global nil :daily 1000 100))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list lim) 500)))
    (true (search "Within budget" (orrery/coalton/core:cl-verdict-hint (first verdicts))))))

(define-test (budget-policy actual-tokens)
  (let* ((lim (orrery/coalton/core:cl-make-budget-limit :global nil :daily 1000 100))
         (verdicts (orrery/coalton/core:cl-evaluate-policy (list lim) 777)))
    (is = 777 (orrery/coalton/core:cl-verdict-actual (first verdicts)))))
