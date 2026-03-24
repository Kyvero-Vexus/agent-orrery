;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; audit-trail-tests.lisp — Tests for Coalton audit-trail module
;;;
;;; Bead: agent-orrery-b0s7 (eb0.8.1)

(in-package #:orrery/harness-tests)

(define-test audit-trail-tests)

;; Stub hash function for testing: returns predictable 64-char hex
(defun stub-hash (input)
  "Simple deterministic hash for tests. Real impl uses SHA-256."
  (declare (ignore input))
  (format nil "~64,'0X" (sxhash input)))

(define-test (audit-trail-tests empty-trail-has-count-0)
  (let ((trail (orrery/coalton/core:cl-empty-trail)))
    (is = 0 (orrery/coalton/core:cl-trail-count trail))))

(define-test (audit-trail-tests empty-trail-genesis-hash)
  (let ((trail (orrery/coalton/core:cl-empty-trail)))
    (is string= "0000000000000000000000000000000000000000000000000000000000000000"
        (orrery/coalton/core:cl-trail-tip-hash trail))))

(define-test (audit-trail-tests append-increments-count)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (trail1 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail
                  1700000000
                  (orrery/coalton/core:cl-audit-session-lifecycle)
                  (orrery/coalton/core:cl-audit-info)
                  "test-actor"
                  "session created"
                  "{\"session_id\":\"abc\"}")))
    (is = 1 (orrery/coalton/core:cl-trail-count trail1))
    (let ((trail2 (orrery/coalton/core:cl-append-entry
                   #'stub-hash trail1
                   1700000001
                   (orrery/coalton/core:cl-audit-model-routing)
                   (orrery/coalton/core:cl-audit-warning)
                   "router"
                   "fallback triggered"
                   "{}")))
      (is = 2 (orrery/coalton/core:cl-trail-count trail2)))))

(define-test (audit-trail-tests tip-hash-changes-on-append)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (hash0 (orrery/coalton/core:cl-trail-tip-hash trail))
         (trail1 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail
                  1700000000
                  (orrery/coalton/core:cl-audit-session-lifecycle)
                  (orrery/coalton/core:cl-audit-info)
                  "test-actor"
                  "session created"
                  "{}"))
         (hash1 (orrery/coalton/core:cl-trail-tip-hash trail1)))
    (is string/= hash0 hash1)
    (is = 64 (length hash1))))

(define-test (audit-trail-tests verify-empty-trail)
  (let ((trail (orrery/coalton/core:cl-empty-trail)))
    (is eq t (orrery/coalton/core:cl-verify-trail #'stub-hash trail))))

(define-test (audit-trail-tests verify-single-entry-trail)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (trail1 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail
                  1700000000
                  (orrery/coalton/core:cl-audit-session-lifecycle)
                  (orrery/coalton/core:cl-audit-info)
                  "test-actor"
                  "session created"
                  "{}")))
    (is eq t (orrery/coalton/core:cl-verify-trail #'stub-hash trail1))))

(define-test (audit-trail-tests verify-multi-entry-chain)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (trail1 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail
                  1700000000
                  (orrery/coalton/core:cl-audit-session-lifecycle)
                  (orrery/coalton/core:cl-audit-info)
                  "actor1"
                  "created"
                  "{}"))
         (trail2 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail1
                  1700000001
                  (orrery/coalton/core:cl-audit-cron-execution)
                  (orrery/coalton/core:cl-audit-warning)
                  "actor2"
                  "warning"
                  "{}"))
         (trail3 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail2
                  1700000002
                  (orrery/coalton/core:cl-audit-policy-change)
                  (orrery/coalton/core:cl-audit-critical)
                  "actor3"
                  "critical"
                  "{}")))
    (is eq t (orrery/coalton/core:cl-verify-trail #'stub-hash trail3))))

(define-test (audit-trail-tests entry-accessors)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (entry (orrery/coalton/core:cl-make-single-entry
                 #'stub-hash trail
                 1700000000
                 (orrery/coalton/core:cl-audit-model-routing)
                 (orrery/coalton/core:cl-audit-warning)
                 "router"
                 "fallback to haiku"
                 "{\"from\":\"claude\",\"to\":\"haiku\"}")))
    (is = 0 (orrery/coalton/core:cl-entry-seq entry))
    (is = 1700000000 (orrery/coalton/core:cl-entry-timestamp entry))
    (is string= "model-routing" (orrery/coalton/core:cl-entry-category-label entry))
    (is string= "warning" (orrery/coalton/core:cl-entry-severity-label entry))
    (is string= "router" (orrery/coalton/core:cl-entry-actor entry))
    (is string= "fallback to haiku" (orrery/coalton/core:cl-entry-summary entry))
    (is string= "{\"from\":\"claude\",\"to\":\"haiku\"}" (orrery/coalton/core:cl-entry-detail entry))
    (is = 64 (length (orrery/coalton/core:cl-entry-hash entry)))
    (is string= "0000000000000000000000000000000000000000000000000000000000000000"
        (orrery/coalton/core:cl-entry-prev-hash entry))))

(define-test (audit-trail-tests count-by-severity)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (trail1 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail
                  1700000000
                  (orrery/coalton/core:cl-audit-session-lifecycle)
                  (orrery/coalton/core:cl-audit-info)
                  "a" "s1" "{}"))
         (trail2 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail1
                  1700000001
                  (orrery/coalton/core:cl-audit-cron-execution)
                  (orrery/coalton/core:cl-audit-warning)
                  "a" "s2" "{}"))
         (trail3 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail2
                  1700000002
                  (orrery/coalton/core:cl-audit-policy-change)
                  (orrery/coalton/core:cl-audit-warning)
                  "a" "s3" "{}"))
         (trail4 (orrery/coalton/core:cl-append-entry
                  #'stub-hash trail3
                  1700000003
                  (orrery/coalton/core:cl-audit-config-change)
                  (orrery/coalton/core:cl-audit-critical)
                  "a" "s4" "{}")))
    (is = 1 (orrery/coalton/core:cl-count-by-severity
             (orrery/coalton/core:cl-audit-info) trail4))
    (is = 2 (orrery/coalton/core:cl-count-by-severity
             (orrery/coalton/core:cl-audit-warning) trail4))
    (is = 1 (orrery/coalton/core:cl-count-by-severity
             (orrery/coalton/core:cl-audit-critical) trail4))
    (is = 0 (orrery/coalton/core:cl-count-by-severity
             (orrery/coalton/core:cl-audit-trace) trail4))))

(define-test (audit-trail-tests category-labels-via-entry)
  ;; Test category labels by creating entries and checking their labels
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (entry (orrery/coalton/core:cl-make-single-entry
                 #'stub-hash trail
                 1700000000
                 (orrery/coalton/core:cl-audit-model-routing)
                 (orrery/coalton/core:cl-audit-info)
                 "test" "test" "{}")))
    (is string= "model-routing" (orrery/coalton/core:cl-entry-category-label entry)))
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (entry (orrery/coalton/core:cl-make-single-entry
                 #'stub-hash trail
                 1700000000
                 (orrery/coalton/core:cl-audit-session-lifecycle)
                 (orrery/coalton/core:cl-audit-info)
                 "test" "test" "{}")))
    (is string= "session-lifecycle" (orrery/coalton/core:cl-entry-category-label entry))))

(define-test (audit-trail-tests severity-labels-via-entry)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (entry (orrery/coalton/core:cl-make-single-entry
                 #'stub-hash trail
                 1700000000
                 (orrery/coalton/core:cl-audit-session-lifecycle)
                 (orrery/coalton/core:cl-audit-warning)
                 "test" "test" "{}")))
    (is string= "warning" (orrery/coalton/core:cl-entry-severity-label entry)))
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (entry (orrery/coalton/core:cl-make-single-entry
                 #'stub-hash trail
                 1700000000
                 (orrery/coalton/core:cl-audit-session-lifecycle)
                 (orrery/coalton/core:cl-audit-critical)
                 "test" "test" "{}")))
    (is string= "critical" (orrery/coalton/core:cl-entry-severity-label entry))))
