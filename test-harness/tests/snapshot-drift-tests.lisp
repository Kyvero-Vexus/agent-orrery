;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; snapshot-drift-tests.lisp — Tests for snapshot drift diagnostic (3nk)

(in-package #:orrery/harness-tests)

(define-test snapshot-drift-tests)

;;; ─── Helper: build a fixture capture snapshot ───

(defun %make-test-snapshot (&key (id "test-snap")
                                  (profile :fixture)
                                  (samples nil))
  "Build a capture snapshot for testing."
  (orrery/adapter:make-capture-snapshot
   :snapshot-id id
   :target (orrery/adapter:make-capture-target
            :base-url "http://test" :token "" :profile profile)
   :samples (or samples
                (list
                 (orrery/adapter:make-endpoint-sample
                  :endpoint "/api/v1/health"
                  :status-code 200
                  :body "{\"status\":\"ok\"}"
                  :latency-ms 1 :timestamp 100 :error-p nil)
                 (orrery/adapter:make-endpoint-sample
                  :endpoint "/api/v1/sessions"
                  :status-code 200
                  :body "{\"sessions\":[]}"
                  :latency-ms 1 :timestamp 101 :error-p nil)
                 (orrery/adapter:make-endpoint-sample
                  :endpoint "/api/v1/cron"
                  :status-code 200
                  :body "{\"jobs\":[]}"
                  :latency-ms 1 :timestamp 102 :error-p nil)
                 (orrery/adapter:make-endpoint-sample
                  :endpoint "/api/v1/events"
                  :status-code 200
                  :body "{\"events\":[]}"
                  :latency-ms 1 :timestamp 103 :error-p nil)
                 (orrery/adapter:make-endpoint-sample
                  :endpoint "/api/v1/alerts"
                  :status-code 200
                  :body "{\"alerts\":[]}"
                  :latency-ms 1 :timestamp 104 :error-p nil)
                 (orrery/adapter:make-endpoint-sample
                  :endpoint "/api/v1/usage"
                  :status-code 200
                  :body "{\"usage\":{}}"
                  :latency-ms 1 :timestamp 105 :error-p nil)))
   :timestamp 100
   :duration-ms 3))

;;; ─── analyze-snapshot-drift ───

(define-test (snapshot-drift-tests clean-fixture-snapshot)
  :description "All endpoints match schema → disposition :clean"
  (let ((diag (orrery/adapter:analyze-snapshot-drift (%make-test-snapshot))))
    (is eq :clean (orrery/adapter:sdd-disposition diag))
    (is = 0 (orrery/adapter:sdd-breaking-count diag))
    (is = 0 (orrery/adapter:sdd-degrading-count diag))
    (is string= "test-snap" (orrery/adapter:sdd-snapshot-id diag))
    (is eq :fixture (orrery/adapter:sdd-profile diag))
    (true (plusp (orrery/adapter:sdd-endpoint-count diag)))))

(define-test (snapshot-drift-tests missing-required-field-breaking)
  :description "Missing required field → breaking finding, disposition :incompatible"
  (let* ((samples (list
                   (orrery/adapter:make-endpoint-sample
                    :endpoint "/api/v1/health"
                    :status-code 200
                    :body "{\"version\":\"1.0\"}"
                    :latency-ms 1 :timestamp 100 :error-p nil)))
         (snap (%make-test-snapshot :samples samples))
         (diag (orrery/adapter:analyze-snapshot-drift
                snap
                :schemas (list (first orrery/adapter:*snapshot-endpoint-schemas*)))))
    (is eq :incompatible (orrery/adapter:sdd-disposition diag))
    (is = 1 (orrery/adapter:sdd-breaking-count diag))))

(define-test (snapshot-drift-tests type-mismatch-degraded)
  :description "Type mismatch → degrading finding, disposition :degraded"
  (let* ((samples (list
                   (orrery/adapter:make-endpoint-sample
                    :endpoint "/api/v1/health"
                    :status-code 200
                    :body "{\"status\":42}"
                    :latency-ms 1 :timestamp 100 :error-p nil)))
         (snap (%make-test-snapshot :samples samples))
         (diag (orrery/adapter:analyze-snapshot-drift
                snap
                :schemas (list (first orrery/adapter:*snapshot-endpoint-schemas*)))))
    (is eq :degraded (orrery/adapter:sdd-disposition diag))
    (is = 1 (orrery/adapter:sdd-degrading-count diag))))

(define-test (snapshot-drift-tests extra-fields-clean)
  :description "Extra fields are info-only → disposition still :clean"
  (let* ((samples (list
                   (orrery/adapter:make-endpoint-sample
                    :endpoint "/api/v1/health"
                    :status-code 200
                    :body "{\"status\":\"ok\",\"uptime\":12345}"
                    :latency-ms 1 :timestamp 100 :error-p nil)))
         (snap (%make-test-snapshot :samples samples))
         (diag (orrery/adapter:analyze-snapshot-drift
                snap
                :schemas (list (first orrery/adapter:*snapshot-endpoint-schemas*)))))
    (is eq :clean (orrery/adapter:sdd-disposition diag))
    (true (plusp (orrery/adapter:sdd-info-count diag)))))

(define-test (snapshot-drift-tests error-samples-excluded)
  :description "Error samples excluded from drift analysis"
  (let* ((samples (list
                   (orrery/adapter:make-endpoint-sample
                    :endpoint "/api/v1/health"
                    :status-code 0
                    :body ""
                    :latency-ms 5000 :timestamp 100 :error-p t)))
         (snap (%make-test-snapshot :samples samples))
         (diag (orrery/adapter:analyze-snapshot-drift
                snap
                :schemas (list (first orrery/adapter:*snapshot-endpoint-schemas*)))))
    ;; No payload → breaking (no-payload drift)
    (is eq :incompatible (orrery/adapter:sdd-disposition diag))
    (is = 1 (orrery/adapter:sdd-breaking-count diag))))

(define-test (snapshot-drift-tests gate-evidence-ref-format)
  :description "Gate evidence ref contains snapshot ID and disposition"
  (let ((diag (orrery/adapter:analyze-snapshot-drift (%make-test-snapshot))))
    (true (search "test-snap" (orrery/adapter:sdd-gate-evidence-ref diag)))
    (true (search "clean" (orrery/adapter:sdd-gate-evidence-ref diag)))))

;;; ─── compare-snapshot-drifts ───

(define-test (snapshot-drift-tests comparison-both-clean)
  :description "Both fixture and live clean → compatible"
  (let* ((f-snap (%make-test-snapshot :id "fixture-snap" :profile :fixture))
         (l-snap (%make-test-snapshot :id "live-snap" :profile :live))
         (f-diag (orrery/adapter:analyze-snapshot-drift f-snap))
         (l-diag (orrery/adapter:analyze-snapshot-drift l-snap))
         (comp (orrery/adapter:compare-snapshot-drifts f-diag l-diag)))
    (true (orrery/adapter:dc-compatible-p comp))
    (is = 0 (length (orrery/adapter:dc-regression-endpoints comp)))
    (is = 0 (length (orrery/adapter:dc-new-drifts comp)))
    (true (search "0 regressions" (orrery/adapter:dc-summary comp)))))

(define-test (snapshot-drift-tests comparison-live-regressed)
  :description "Live has breaking drift that fixture didn't → regression detected"
  (let* ((f-snap (%make-test-snapshot :id "f" :profile :fixture))
         (l-samples (list
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/health"
                      :status-code 200
                      :body "{\"version\":\"2.0\"}"
                      :latency-ms 1 :timestamp 100 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/sessions"
                      :status-code 200
                      :body "{\"sessions\":[]}"
                      :latency-ms 1 :timestamp 101 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/cron"
                      :status-code 200
                      :body "{\"jobs\":[]}"
                      :latency-ms 1 :timestamp 102 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/events"
                      :status-code 200
                      :body "{\"events\":[]}"
                      :latency-ms 1 :timestamp 103 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/alerts"
                      :status-code 200
                      :body "{\"alerts\":[]}"
                      :latency-ms 1 :timestamp 104 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/usage"
                      :status-code 200
                      :body "{\"usage\":{}}"
                      :latency-ms 1 :timestamp 105 :error-p nil)))
         (l-snap (%make-test-snapshot :id "l" :profile :live :samples l-samples))
         (f-diag (orrery/adapter:analyze-snapshot-drift f-snap))
         (l-diag (orrery/adapter:analyze-snapshot-drift l-snap))
         (comp (orrery/adapter:compare-snapshot-drifts f-diag l-diag)))
    (false (orrery/adapter:dc-compatible-p comp))
    (true (find "/api/v1/health" (orrery/adapter:dc-regression-endpoints comp)
                :test #'string=))))

(define-test (snapshot-drift-tests comparison-resolved-drift)
  :description "Fixture had drift that live resolved"
  (let* ((f-samples (list
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/health"
                      :status-code 200
                      :body "{\"version\":\"2.0\"}"
                      :latency-ms 1 :timestamp 100 :error-p nil)))
         (l-samples (list
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/health"
                      :status-code 200
                      :body "{\"status\":\"ok\"}"
                      :latency-ms 1 :timestamp 100 :error-p nil)))
         (health-only (list (first orrery/adapter:*snapshot-endpoint-schemas*)))
         (f-snap (%make-test-snapshot :id "f" :profile :fixture :samples f-samples))
         (l-snap (%make-test-snapshot :id "l" :profile :live :samples l-samples))
         (f-diag (orrery/adapter:analyze-snapshot-drift f-snap :schemas health-only))
         (l-diag (orrery/adapter:analyze-snapshot-drift l-snap :schemas health-only))
         (comp (orrery/adapter:compare-snapshot-drifts f-diag l-diag)))
    (true (plusp (length (orrery/adapter:dc-resolved-drifts comp))))))

;;; ─── JSON serialization ───

(define-test (snapshot-drift-tests diagnostic-json-roundtrip)
  :description "Diagnostic JSON contains required fields"
  (let* ((diag (orrery/adapter:analyze-snapshot-drift (%make-test-snapshot)))
         (json (orrery/adapter:snapshot-drift-diagnostic-to-json diag)))
    (true (search "\"snapshot_id\":\"test-snap\"" json))
    (true (search "\"disposition\":\"clean\"" json))
    (true (search "\"breaking\":0" json))
    (true (search "\"drift_reports\":[" json))
    (true (search "\"gate_evidence_ref\":" json))))

(define-test (snapshot-drift-tests comparison-json-roundtrip)
  :description "Comparison JSON contains required fields"
  (let* ((f-snap (%make-test-snapshot :id "f" :profile :fixture))
         (l-snap (%make-test-snapshot :id "l" :profile :live))
         (f-diag (orrery/adapter:analyze-snapshot-drift f-snap))
         (l-diag (orrery/adapter:analyze-snapshot-drift l-snap))
         (comp (orrery/adapter:compare-snapshot-drifts f-diag l-diag))
         (json (orrery/adapter:drift-comparison-to-json comp)))
    (true (search "\"compatible\":true" json))
    (true (search "\"summary\":" json))
    (true (search "\"fixture\":" json))
    (true (search "\"live\":" json))
    (true (search "\"regression_endpoints\":[]" json))))

(define-test (snapshot-drift-tests incompatible-json-has-details)
  :description "Incompatible comparison JSON has regression details"
  (let* ((f-snap (%make-test-snapshot :id "f" :profile :fixture))
         (l-samples (list
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/health"
                      :status-code 200
                      :body "{\"version\":\"2.0\"}"
                      :latency-ms 1 :timestamp 100 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/sessions"
                      :status-code 200
                      :body "{\"sessions\":[]}"
                      :latency-ms 1 :timestamp 101 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/cron"
                      :status-code 200
                      :body "{\"jobs\":[]}"
                      :latency-ms 1 :timestamp 102 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/events"
                      :status-code 200
                      :body "{\"events\":[]}"
                      :latency-ms 1 :timestamp 103 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/alerts"
                      :status-code 200
                      :body "{\"alerts\":[]}"
                      :latency-ms 1 :timestamp 104 :error-p nil)
                     (orrery/adapter:make-endpoint-sample
                      :endpoint "/api/v1/usage"
                      :status-code 200
                      :body "{\"usage\":{}}"
                      :latency-ms 1 :timestamp 105 :error-p nil)))
         (l-snap (%make-test-snapshot :id "l" :profile :live :samples l-samples))
         (f-diag (orrery/adapter:analyze-snapshot-drift f-snap))
         (l-diag (orrery/adapter:analyze-snapshot-drift l-snap))
         (comp (orrery/adapter:compare-snapshot-drifts f-diag l-diag))
         (json (orrery/adapter:drift-comparison-to-json comp)))
    (true (search "\"compatible\":false" json))
    (true (search "/api/v1/health" json))))
