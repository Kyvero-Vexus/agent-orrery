;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
(in-package #:orrery/harness-tests)

(define-test anomaly-detector)

(defun %mk-usage (model prompt completion ts)
  (declare (type string model)
           (type fixnum prompt completion ts)
           (optimize (safety 3)))
  (orrery/domain:make-usage-record
   :model model
   :period :hourly
   :timestamp ts
   :prompt-tokens prompt
   :completion-tokens completion
   :total-tokens (+ prompt completion)
   :estimated-cost-cents (orrery/coalton/core:estimate-cost-cents (+ prompt completion))))

(define-test (anomaly-detector deviation-permille)
  (is = 0 (orrery/coalton/core:cl-deviation-permille 100 100))
  (is = 500 (orrery/coalton/core:cl-deviation-permille 150 100))
  (is = 1000 (orrery/coalton/core:cl-deviation-permille 1 0)))

(define-test (anomaly-detector session-drift-critical)
  (let* ((th (orrery/coalton/core:cl-default-thresholds))
         (findings (orrery/coalton/core:cl-detect-session-drift th 30 10)))
    (is = 1 (length findings))
    (is string=
        "critical"
        (orrery/coalton/core:cl-anomaly-severity-label
         (orrery/coalton/core:af-severity (first findings))))))

(define-test (anomaly-detector cost-runaway-warning)
  (let* ((th (orrery/coalton/core:cl-default-thresholds))
         (findings (orrery/coalton/core:cl-detect-cost-runaway th 140 100)))
    (is = 1 (length findings))
    (is string=
        "warning"
        (orrery/coalton/core:cl-anomaly-severity-label
         (orrery/coalton/core:af-severity (first findings))))))

(define-test (anomaly-detector pipeline-end-to-end)
  (let* ((th (orrery/coalton/core:cl-default-thresholds))
         (e1 (orrery/coalton/core:cl-make-usage-entry "gpt-4" 1000 500 0))
         (e2 (orrery/coalton/core:cl-make-usage-entry "claude" 100 50 0))
         (base-bucket (orrery/coalton/core:cl-aggregate-entries "baseline" (list e2)))
         (cur-bucket (orrery/coalton/core:cl-aggregate-entries "current" (list e1)))
         (base-summary (orrery/coalton/core:cl-build-summary (list base-bucket)))
         (cur-summary (orrery/coalton/core:cl-build-summary (list cur-bucket)))
         (base-models (orrery/coalton/core:cl-summary-top-models base-summary))
         (cur-models (orrery/coalton/core:cl-summary-top-models cur-summary))
         (report (orrery/coalton/core:cl-run-anomaly-pipeline
                  th
                  20 10
                  (orrery/coalton/core:cl-summary-total-cost cur-summary)
                  (orrery/coalton/core:cl-summary-total-cost base-summary)
                  (orrery/coalton/core:cl-summary-total-tokens cur-summary)
                  (orrery/coalton/core:cl-summary-total-tokens base-summary)
                  cur-models base-models)))
    (true (> (orrery/coalton/core:cl-anomaly-report-count report) 0))
    (true (> (orrery/coalton/core:cl-anomaly-report-risk-score report) 0))))

(define-test (anomaly-detector adapter-bridge)
  (let* ((baseline-usage (list (%mk-usage "claude" 80 20 1000)
                               (%mk-usage "claude" 70 30 1001)))
         (current-usage (list (%mk-usage "gpt-4" 900 400 2000)
                              (%mk-usage "gpt-4" 800 300 2001)))
         (baseline (orrery/adapter:make-adapter-anomaly-snapshot
                    :adapter-id "adapter-a"
                    :session-count 8
                    :usage-records baseline-usage))
         (current (orrery/adapter:make-adapter-anomaly-snapshot
                   :adapter-id "adapter-b"
                   :session-count 24
                   :usage-records current-usage))
         (result (orrery/adapter:detect-adapter-anomalies current baseline))
         (json (orrery/adapter:anomaly-result->json result)))
    (true (member (orrery/adapter:adapter-anomaly-result-severity-label result)
                  '(:warning :critical)))
    (true (> (orrery/adapter:adapter-anomaly-result-anomaly-count result) 0))
    (true (search "risk_score" json))))
