;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
(in-package #:orrery/harness-tests)

(define-test usage-analytics)

(define-test (usage-analytics entry-total-tokens)
  (let ((e (orrery/coalton/core:cl-make-usage-entry "gpt-4" 100 50 1000)))
    (is = 150 (orrery/coalton/core:ue-total-tokens e))))

(define-test (usage-analytics entry-cost)
  (let ((e (orrery/coalton/core:cl-make-usage-entry "gpt-4" 1000 500 0)))
    (is = 3 (orrery/coalton/core:ue-cost-cents e))))

(define-test (usage-analytics entry-zero)
  (let ((e (orrery/coalton/core:cl-make-usage-entry "test" 0 0 0)))
    (is = 0 (orrery/coalton/core:ue-total-tokens e))
    (is = 0 (orrery/coalton/core:ue-cost-cents e))))

(define-test (usage-analytics aggregate-bucket)
  (let* ((e1 (orrery/coalton/core:cl-make-usage-entry "gpt-4" 100 50 1000))
         (e2 (orrery/coalton/core:cl-make-usage-entry "claude" 200 100 2000))
         (bucket (orrery/coalton/core:cl-aggregate-entries "hourly" (list e1 e2))))
    (is = 450 (orrery/coalton/core:bucket-total-tokens bucket))
    (true (> (orrery/coalton/core:bucket-total-cost bucket) 0))
    (is string= "hourly" (orrery/coalton/core:bucket-period bucket))))

(define-test (usage-analytics summary)
  (let* ((e1 (orrery/coalton/core:cl-make-usage-entry "gpt-4" 100 50 0))
         (e2 (orrery/coalton/core:cl-make-usage-entry "claude" 200 100 0))
         (b1 (orrery/coalton/core:cl-aggregate-entries "h1" (list e1)))
         (b2 (orrery/coalton/core:cl-aggregate-entries "h2" (list e2)))
         (summary (orrery/coalton/core:cl-build-summary (list b1 b2))))
    (is = 450 (orrery/coalton/core:cl-summary-total-tokens summary))
    (true (> (orrery/coalton/core:cl-summary-total-cost summary) 0))))

(define-test (usage-analytics bridge-record->entry)
  (let* ((rec (orrery/domain:make-usage-record
               :model "gpt-4" :period :hourly :timestamp 1000
               :prompt-tokens 100 :completion-tokens 50
               :total-tokens 150 :estimated-cost-cents 1))
         (entry (usage-record->coalton-entry rec)))
    (is = 150 (orrery/coalton/core:ue-total-tokens entry))
    (is string= "gpt-4" (orrery/coalton/core:ue-model entry))))

(define-test (usage-analytics bridge-records->bucket)
  (let* ((r1 (orrery/domain:make-usage-record
              :model "a" :period :hourly :timestamp 0
              :prompt-tokens 50 :completion-tokens 25
              :total-tokens 75 :estimated-cost-cents 0))
         (bucket (usage-records->coalton-bucket (list r1) "test")))
    (is = 75 (orrery/coalton/core:bucket-total-tokens bucket))))

(define-test (usage-analytics bridge-json)
  (let* ((e1 (orrery/coalton/core:cl-make-usage-entry "gpt-4" 100 50 0))
         (b (orrery/coalton/core:cl-aggregate-entries "h1" (list e1)))
         (summary (orrery/coalton/core:cl-build-summary (list b)))
         (json (coalton-summary->json summary)))
    (true (search "total_tokens" json))
    (true (search "150" json))))
