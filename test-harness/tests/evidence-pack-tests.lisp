;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; evidence-pack-tests.lisp — Tests for Epic 2 gate evidence pack
;;;

(in-package #:orrery/harness-tests)

(define-test evidence-pack-suite)

;;; ─── simple-body-hash ───

(define-test (evidence-pack-suite hash-empty)
  (true (stringp (simple-body-hash ""))))

(define-test (evidence-pack-suite hash-short)
  (true (search "abc" (simple-body-hash "abc"))))

(define-test (evidence-pack-suite hash-normal)
  (let ((h (simple-body-hash "{\"sessions\":[]}")))
    (true (> (length h) 0))))

;;; ─── compare-endpoint-samples ───

(define-test (evidence-pack-suite compare-identical)
  (let* ((s (make-endpoint-sample :endpoint "/api/v1/sessions" :status-code 200
                                   :body "{\"sessions\":[]}" :latency-ms 10))
         (entry (compare-endpoint-samples s s)))
    (is eq :identical (pe-verdict entry))))

(define-test (evidence-pack-suite compare-different-status)
  (let* ((fix (make-endpoint-sample :endpoint "/api/v1/health" :status-code 200
                                     :body "{}" :latency-ms 10))
         (live (make-endpoint-sample :endpoint "/api/v1/health" :status-code 500
                                      :body "{}" :latency-ms 100))
         (entry (compare-endpoint-samples fix live)))
    (false (eq :identical (pe-verdict entry)))))

;;; ─── build-parity-report ───

(define-test (evidence-pack-suite parity-fixture-vs-fixture)
  (let* ((target (make-capture-target :base-url "http://fix" :profile :fixture))
         (snap1 (assemble-snapshot target (mapcar #'car orrery/adapter::*fixture-endpoints*) 1000 "s1"))
         (snap2 (assemble-snapshot target (mapcar #'car orrery/adapter::*fixture-endpoints*) 2000 "s2"))
         (report (build-parity-report snap1 snap2 "par-001" 2000)))
    (is eq :identical (pr-overall-verdict report))
    (true (> (length (pr-entries report)) 0))))

(define-test (evidence-pack-suite parity-fixture-vs-live)
  (let* ((fix-target (make-capture-target :base-url "http://fix" :profile :fixture))
         (live-target (make-capture-target :base-url "http://live" :token "t" :profile :live))
         (fix-snap (assemble-snapshot fix-target (mapcar #'car orrery/adapter::*fixture-endpoints*) 1000 "fx"))
         (live-snap (assemble-snapshot live-target (mapcar #'car orrery/adapter::*fixture-endpoints*) 2000 "lv"))
         (report (build-parity-report fix-snap live-snap "par-002" 2000)))
    (false (eq :identical (pr-overall-verdict report)))))

;;; ─── build-replay-manifest ───

(define-test (evidence-pack-suite manifest-single)
  (let* ((s1 (make-replay-stream :stream-id "s1" :source :fixture
                                  :events (list (make-replay-event :sequence-id 1 :event-type :session :payload "d"))
                                  :seed 42))
         (a1 (make-artifact-envelope :artifact-id "a1" :kind :replay-stream
                                      :version "1.0.0" :checksum "abc" :payload-size 10))
         (manifest (build-replay-manifest (list s1) (list a1) "m-001" 5000)))
    (is string= "m-001" (rm-manifest-id manifest))
    (is = 1 (rm-stream-count manifest))))

;;; ─── build-evidence-pack ───

(define-test (evidence-pack-suite pack-fixture-vs-live)
  (let* ((fix (run-capture (make-capture-target :profile :fixture) :timestamp 1000 :snapshot-id "fix"))
         (live (run-capture (make-capture-target :base-url "http://live" :token "t" :profile :live) :timestamp 2000 :snapshot-id "live"))
         (pack (build-evidence-pack fix live :pack-id "ep-test" :timestamp 3000)))
    (is string= "ep-test" (ep-pack-id pack))
    (is = 3000 (ep-timestamp pack))
    (true (evidence-pack-p pack))
    ;; Live blocked → not gate-ready
    (false (ep-gate-ready-p pack))
    (true (> (length (ep-blockers pack)) 0))))

(define-test (evidence-pack-suite pack-fixture-vs-fixture)
  (let* ((fix1 (run-capture (make-capture-target :profile :fixture) :timestamp 1000 :snapshot-id "f1"))
         (fix2 (run-capture (make-capture-target :profile :fixture) :timestamp 2000 :snapshot-id "f2"))
         (pack (build-evidence-pack fix1 fix2 :pack-id "ep-ff" :timestamp 4000)))
    ;; Fixture vs fixture → gate-ready
    (true (ep-gate-ready-p pack))))

;;; ─── JSON serialization ───

(define-test (evidence-pack-suite parity-json)
  (let* ((target (make-capture-target :base-url "http://fix" :profile :fixture))
         (snap1 (assemble-snapshot target '("/api/v1/sessions") 1000 "s1"))
         (snap2 (assemble-snapshot target '("/api/v1/sessions") 2000 "s2"))
         (report (build-parity-report snap1 snap2 "r-001" 2000))
         (json (parity-report-to-json report)))
    (true (search "report_id" json))
    (true (search "r-001" json))))

(define-test (evidence-pack-suite manifest-json)
  (let* ((s1 (make-replay-stream :stream-id "s1" :source :fixture
                                  :events (list (make-replay-event :sequence-id 1 :event-type :session :payload "x"))
                                  :seed 42))
         (a1 (make-artifact-envelope :artifact-id "a1" :kind :replay-stream :version "1.0.0" :checksum "x" :payload-size 1))
         (manifest (build-replay-manifest (list s1) (list a1) "m-json" 0))
         (json (replay-manifest-to-json manifest)))
    (true (search "manifest_id" json))))

(define-test (evidence-pack-suite pack-json)
  (let* ((fix (run-capture (make-capture-target :profile :fixture) :timestamp 1000 :snapshot-id "jf"))
         (live (run-capture (make-capture-target :base-url "http://live" :token "t" :profile :live) :timestamp 2000 :snapshot-id "jl"))
         (pack (build-evidence-pack fix live :pack-id "ep-json"))
         (json (evidence-pack-to-json pack)))
    (true (search "pack_id" json))
    (true (search "ep-json" json))))

;;; ─── Integration ───

(define-test (evidence-pack-suite full-epic2-integration)
  (let* ((fix (run-capture (make-capture-target :profile :fixture) :snapshot-id "integ-fix" :timestamp 1000))
         (live (run-capture (make-capture-target :base-url "http://live" :token "t" :profile :live) :snapshot-id "integ-live" :timestamp 2000))
         (pack (build-evidence-pack fix live :pack-id "integ-001" :timestamp 5000))
         (json (evidence-pack-to-json pack)))
    (true (evidence-pack-p pack))
    (true (> (length json) 100))
    (true (> (length (ep-repro-commands pack)) 0))))
