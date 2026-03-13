;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; normalization-tests.lisp — typed normalization pipeline tests

(in-package #:orrery/harness-tests)

(define-test normalization-tests)

(defun %ht (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr
          do (setf (gethash k h) v))
    h))

(define-test (normalization-tests timestamp-coercion)
  (is = 42 (normalize-timestamp 42))
  (is = 42 (normalize-timestamp 42.9))
  (is = 42 (normalize-timestamp "42"))
  (is = 0 (normalize-timestamp "not-a-number")))

(define-test (normalization-tests session-normalization-missing-fields)
  (let ((s (normalize-session-payload (%ht "id" "s1" "status" "active" "total_tokens" "123"))))
    (true (session-record-p s))
    (is string= "s1" (sr-id s))
    (is eq :active (sr-status s))
    (is = 123 (sr-total-tokens s))))

(define-test (normalization-tests event-and-alert-normalization)
  (let* ((e (normalize-event-payload (%ht "id" "e1" "kind" "warning" "timestamp" "1700")))
         (a (normalize-alert-payload (%ht "id" "a1" "severity" "critical" "acknowledged" t "fired_at" 99))))
    (true (event-record-p e))
    (true (alert-record-p a))
    (is eq :warning (er-kind e))
    (is = 1700 (er-timestamp e))
    (is eq :critical (ar-severity a))
    (true (ar-acknowledged-p a))))

(define-test (normalization-tests snapshot-normalization)
  (let* ((snap (normalize-snapshot-payload
                (%ht "sync_token" "tok-1"
                     "sessions" (vector (%ht "id" "s1"))
                     "events" (vector (%ht "id" "e1" "kind" "info"))
                     "alerts" (vector (%ht "id" "a1"))))))
    (true (normalized-snapshot-p snap))
    (is string= "tok-1" (normalized-snapshot-sync-token snap))
    (is = 1 (length (normalized-snapshot-sessions snap)))
    (is = 1 (length (normalized-snapshot-events snap)))
    (is = 1 (length (normalized-snapshot-alerts snap)))))
