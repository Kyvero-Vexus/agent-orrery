;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capture-driver-tests.lisp — Tests for capture driver
;;;

(in-package #:orrery/harness-tests)

(define-test capture-driver)

;;; ─── Helpers ───

(defun make-fixture-target ()
  (make-capture-target :base-url "http://fixture" :profile :fixture))

(defun make-live-target ()
  (make-capture-target :base-url "http://live:18789" :token "tok" :profile :live))

;;; ─── sample-fixture-endpoint ───

(define-test (capture-driver fixture-known-endpoint)
  (let ((s (sample-fixture-endpoint (make-fixture-target) "/api/v1/sessions" 1000)))
    (is = 200 (es-status-code s))
    (false (es-error-p s))
    (true (> (length (es-body s)) 0))
    (is = 1000 (es-timestamp s))))

(define-test (capture-driver fixture-unknown-endpoint)
  (let ((s (sample-fixture-endpoint (make-fixture-target) "/api/v1/unknown" 1000)))
    (is = 404 (es-status-code s))
    (true (es-error-p s))))

(define-test (capture-driver fixture-all-standard-endpoints)
  (let ((target (make-fixture-target)))
    (dolist (pair orrery/adapter::*fixture-endpoints*)
      (let ((s (sample-fixture-endpoint target (car pair) 0)))
        (is = 200 (es-status-code s))
        (false (es-error-p s))))))

;;; ─── sample-endpoint ───

(define-test (capture-driver sample-fixture-dispatch)
  (let ((s (sample-endpoint (make-fixture-target) "/api/v1/health" 500)))
    (is = 200 (es-status-code s))))

(define-test (capture-driver sample-live-returns-error)
  ;; Live without env wiring returns transport error
  (let ((s (sample-endpoint (make-live-target) "/api/v1/sessions" 500)))
    (true (es-error-p s))
    (is = 0 (es-status-code s))))

;;; ─── normalize-sample-to-finding ───

(define-test (capture-driver normalize-healthy-200)
  (let* ((s (make-endpoint-sample :endpoint "/api/v1/health" :status-code 200
                                   :body "{}" :latency-ms 10 :timestamp 1000))
         (f (normalize-sample-to-finding s)))
    (is eq :healthy (pf-status f))
    (is eq :transport (pf-domain f))
    (is = 0 (pf-severity f))))

(define-test (capture-driver normalize-error)
  (let* ((s (make-endpoint-sample :endpoint "/api/v1/sessions" :status-code 0
                                   :body "" :latency-ms 5000 :error-p t))
         (f (normalize-sample-to-finding s)))
    (is eq :unhealthy (pf-status f))
    (is eq :runtime (pf-domain f))))

(define-test (capture-driver normalize-404)
  (let* ((s (make-endpoint-sample :endpoint "/api/v1/events" :status-code 404
                                   :body "" :latency-ms 50))
         (f (normalize-sample-to-finding s)))
    (is eq :degraded (pf-status f))))

(define-test (capture-driver normalize-500)
  (let* ((s (make-endpoint-sample :endpoint "/api/v1/alerts" :status-code 500
                                   :body "" :latency-ms 100))
         (f (normalize-sample-to-finding s)))
    (is eq :unhealthy (pf-status f))))

(define-test (capture-driver normalize-evidence-ref)
  (let* ((s (make-endpoint-sample :endpoint "/api/v1/health" :status-code 200
                                   :body "{}" :timestamp 42))
         (f (normalize-sample-to-finding s)))
    (true (search "capture:" (pf-evidence-ref f)))
    (true (search "health" (pf-evidence-ref f)))))

;;; ─── assemble-snapshot ───

(define-test (capture-driver assemble-fixture)
  (let* ((target (make-fixture-target))
         (snapshot (assemble-snapshot target
                                      '("/api/v1/sessions" "/api/v1/health")
                                      1000 "snap-test")))
    (is string= "snap-test" (cs-snapshot-id snapshot))
    (is = 2 (length (cs-samples snapshot)))
    (is = 1000 (cs-timestamp snapshot))))

(define-test (capture-driver assemble-all-endpoints)
  (let* ((target (make-fixture-target))
         (eps (mapcar #'car orrery/adapter::*fixture-endpoints*))
         (snapshot (assemble-snapshot target eps 0 "full")))
    (is = (length eps) (length (cs-samples snapshot)))
    (false (some #'es-error-p (cs-samples snapshot)))))

;;; ─── snapshot-to-artifact ───

(define-test (capture-driver artifact-from-fixture)
  (let* ((target (make-fixture-target))
         (snapshot (assemble-snapshot target '("/api/v1/sessions") 1000 "art-1"))
         (artifact (snapshot-to-artifact snapshot)))
    (true (ae-valid-p artifact))
    (is string= "art-1" (ae-artifact-id artifact))
    (is eq :evidence-bundle (ae-kind artifact))
    (true (search "sha256:" (ae-checksum artifact)))))

(define-test (capture-driver artifact-from-live-invalid)
  (let* ((target (make-live-target))
         (snapshot (assemble-snapshot target '("/api/v1/sessions") 1000 "art-2"))
         (artifact (snapshot-to-artifact snapshot)))
    ;; Live without env wiring → errors → not valid
    (false (ae-valid-p artifact))))

;;; ─── snapshot-to-replay-stream ───

(define-test (capture-driver replay-stream-from-snapshot)
  (let* ((target (make-fixture-target))
         (snapshot (assemble-snapshot target
                                      '("/api/v1/sessions" "/api/v1/health" "/api/v1/events")
                                      1000 "rpl-1"))
         (stream (snapshot-to-replay-stream snapshot)))
    (is string= "rpl-1" (rstr-stream-id stream))
    (is = 3 (length (rstr-events stream)))
    ;; Events should be monotonically ordered
    (let ((ids (mapcar #'re-sequence-id (rstr-events stream))))
      (true (equal ids '(1 2 3))))))

(define-test (capture-driver replay-stream-event-types)
  (let* ((target (make-fixture-target))
         (snapshot (assemble-snapshot target
                                      '("/api/v1/sessions" "/api/v1/cron" "/api/v1/health"
                                        "/api/v1/events" "/api/v1/alerts" "/api/v1/usage")
                                      0 "types-test"))
         (stream (snapshot-to-replay-stream snapshot))
         (types (mapcar #'re-event-type (rstr-events stream))))
    (true (member :session types))
    (true (member :cron types))
    (true (member :health types))
    (true (member :event types))
    (true (member :alert types))
    (true (member :usage types))))

;;; ─── run-capture ───

(define-test (capture-driver run-fixture-success)
  (let ((result (run-capture (make-fixture-target) :timestamp 5000 :snapshot-id "rc-1")))
    (true (cres-success-p result))
    (is = 1 (length (cres-snapshots result)))
    (is = 1 (length (cres-artifacts result)))
    (is = 0 (length (cres-diagnostics result)))))

(define-test (capture-driver run-fixture-custom-endpoints)
  (let ((result (run-capture (make-fixture-target)
                              :endpoints '("/api/v1/sessions" "/api/v1/health")
                              :timestamp 1000)))
    (true (cres-success-p result))
    (is = 2 (length (cs-samples (first (cres-snapshots result)))))))

(define-test (capture-driver run-live-fails-gracefully)
  (let ((result (run-capture (make-live-target) :timestamp 1000)))
    (false (cres-success-p result))
    (true (> (length (cres-diagnostics result)) 0))))

;;; ─── capture-to-decision ───

(define-test (capture-driver decision-from-fixture)
  (let* ((result (run-capture (make-fixture-target) :timestamp 1000))
         (decision (capture-to-decision result)))
    (is eq :pass (dec-verdict decision))
    (is = (length (mapcar #'car orrery/adapter::*fixture-endpoints*))
          (dec-finding-count decision))))

(define-test (capture-driver decision-from-live-fails)
  (let* ((result (run-capture (make-live-target) :timestamp 1000))
         (decision (capture-to-decision result)))
    ;; All endpoints errored → unhealthy → high severity
    (true (member (dec-verdict decision) '(:degraded :fail)))))

;;; ─── Integration: capture → replay → decision → invariant ───

(define-test (capture-driver full-pipeline-integration)
  (let* ((target (make-fixture-target))
         (capture (run-capture target :timestamp 2000 :snapshot-id "integ-1"))
         (snapshot (first (cres-snapshots capture)))
         (stream (snapshot-to-replay-stream snapshot))
         (decision (capture-to-decision capture))
         ;; Schema check (fixture vs fixture → identical)
         (f (make-field-sig :name "status" :field-type :string :required-p t :path "status"))
         (fix-sig (make-schema-sig :endpoint "health" :version "1" :fields (list f)))
         (live-sig (make-schema-sig :endpoint "health" :version "1" :fields (list f)))
         (compat (check-schema-compatibility fix-sig live-sig))
         ;; Run invariants
         (report (run-invariant-suite stream decision compat :timestamp 2000)))
    ;; Fixture → all healthy → pass
    (is eq :pass (dec-verdict decision))
    (true (ir-pass-p report))
    (true (cres-success-p capture))))
