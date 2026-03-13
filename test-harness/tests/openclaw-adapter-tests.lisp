;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; openclaw-adapter-tests.lisp — Tests for OpenClaw adapter client
;;;

(in-package #:orrery/harness-tests)

(define-test openclaw-adapter-tests)

(defclass mock-openclaw-adapter (openclaw-adapter)
  ((responses :initarg :responses :reader mock-responses)))

(defun %make-response-table ()
  (make-hash-table :test 'equal))

(defun %set-response (tbl method path payload)
  (setf (gethash (list method path) tbl) payload)
  tbl)

(defmethod %openclaw-request ((adapter mock-openclaw-adapter) method path &key payload)
  (declare (ignore payload))
  (or (gethash (list method path) (mock-responses adapter))
      (error "No mock response for ~A ~A" method path)))

(defun make-mock-adapter ()
  (let ((tbl (%make-response-table)))
    ;; /sessions
    (%set-response tbl :get "/sessions"
                   (let ((ht (make-hash-table :test 'equal)))
                     (setf (gethash "result" ht)
                           (vector
                            (let ((s (make-hash-table :test 'equal)))
                              (setf (gethash "id" s) "sess-1"
                                    (gethash "agent" s) "ops"
                                    (gethash "channel" s) "webchat"
                                    (gethash "status" s) "active"
                                    (gethash "model" s) "gpt-4"
                                    (gethash "created_at" s) 100
                                    (gethash "updated_at" s) 200
                                    (gethash "message_count" s) 3
                                    (gethash "total_tokens" s) 450
                                    (gethash "estimated_cost_cents" s) 2)
                              s)))
                     ht))

    ;; /sessions/<id>/history
    (%set-response tbl :get "/sessions/sess-1/history"
                   (let ((ht (make-hash-table :test 'equal)))
                     (setf (gethash "result" ht)
                           (vector
                            (let ((m1 (make-hash-table :test 'equal)))
                              (setf (gethash "role" m1) "user"
                                    (gethash "content" m1) "hello"
                                    (gethash "timestamp" m1) 101
                                    (gethash "token_count" m1) 11)
                              m1)
                            (let ((m2 (make-hash-table :test 'equal)))
                              (setf (gethash "role" m2) "assistant"
                                    (gethash "content" m2) "hi"
                                    (gethash "timestamp" m2) 102
                                    (gethash "token_count" m2) 22)
                              m2)))
                     ht))

    ;; /cron/jobs
    (%set-response tbl :get "/cron/jobs"
                   (let ((ht (make-hash-table :test 'equal)))
                     (setf (gethash "result" ht)
                           (vector
                            (let ((j (make-hash-table :test 'equal)))
                              (setf (gethash "name" j) "backup"
                                    (gethash "kind" j) "periodic"
                                    (gethash "interval_s" j) 300
                                    (gethash "status" j) "active"
                                    (gethash "last_run_at" j) 77
                                    (gethash "next_run_at" j) 377
                                    (gethash "run_count" j) 9
                                    (gethash "description" j) "backup job")
                              j)))
                     ht))

    ;; cron command endpoints
    (%set-response tbl :post "/cron/jobs/backup/run" (make-hash-table :test 'equal))
    (%set-response tbl :post "/cron/jobs/backup/pause" (make-hash-table :test 'equal))
    (%set-response tbl :post "/cron/jobs/backup/resume" (make-hash-table :test 'equal))

    ;; /health (single object form)
    (%set-response tbl :get "/health"
                   (let ((h (make-hash-table :test 'equal)))
                     (setf (gethash "component" h) "gateway"
                           (gethash "status" h) "ok"
                           (gethash "message" h) "ready"
                           (gethash "checked_at" h) 999
                           (gethash "latency_ms" h) 12)
                     h))

    (make-instance 'mock-openclaw-adapter
                   :base-url "http://mock"
                   :responses tbl)))

(define-test (openclaw-adapter-tests basic-constructor)
  (let ((a (make-openclaw-adapter :base-url "http://x" :api-token "t" :timeout-s 3)))
    (is string= "http://x" (openclaw-base-url a))
    (is string= "t" (openclaw-api-token a))
    (is = 3 (openclaw-timeout-s a))))

(define-test (openclaw-adapter-tests list-sessions-normalization)
  (let* ((a (make-mock-adapter))
         (sessions (adapter-list-sessions a))
         (s (first sessions)))
    (is = 1 (length sessions))
    (true (session-record-p s))
    (is string= "sess-1" (sr-id s))
    (is eq :active (sr-status s))
    (is = 450 (sr-total-tokens s))))

(define-test (openclaw-adapter-tests session-history-normalization)
  (let* ((a (make-mock-adapter))
         (hist (adapter-session-history a "sess-1")))
    (is = 2 (length hist))
    (true (every #'history-entry-p hist))
    (is eq :user (he-role (first hist)))
    (is = 22 (he-token-count (second hist)))))

(define-test (openclaw-adapter-tests list-cron-normalization)
  (let* ((a (make-mock-adapter))
         (jobs (adapter-list-cron-jobs a))
         (j (first jobs)))
    (is = 1 (length jobs))
    (true (cron-record-p j))
    (is string= "backup" (cr-name j))
    (is eq :periodic (cr-kind j))))

(define-test (openclaw-adapter-tests health-normalization)
  (let* ((a (make-mock-adapter))
         (health (adapter-system-health a))
         (h (first health)))
    (is = 1 (length health))
    (true (health-record-p h))
    (is string= "gateway" (hr-component h))
    (is eq :ok (hr-status h))))

(define-test (openclaw-adapter-tests cron-commands-supported)
  (let ((a (make-mock-adapter)))
    (true (adapter-trigger-cron a "backup"))
    (true (adapter-pause-cron a "backup"))
    (true (adapter-resume-cron a "backup"))))

(define-test (openclaw-adapter-tests unsupported-operations-signal)
  (let ((a (make-mock-adapter)))
    (fail (adapter-list-alerts a) adapter-not-supported)
    (fail (adapter-acknowledge-alert a "a1") adapter-not-supported)
    (fail (adapter-snooze-alert a "a1" 10) adapter-not-supported)
    (fail (adapter-list-subagents a) adapter-not-supported)
    (fail (adapter-tail-events a :since 0 :limit 10) adapter-not-supported)
    (fail (adapter-usage-records a :period :hourly) adapter-not-supported)))

(define-test (openclaw-adapter-tests capabilities-surface)
  (let ((caps (adapter-capabilities (make-mock-adapter))))
    (true (plusp (length caps)))
    (let ((trigger (find "trigger-cron" caps :key #'cap-name :test #'string=))
          (ack (find "acknowledge-alert" caps :key #'cap-name :test #'string=)))
      (true trigger)
      (true (cap-supported-p trigger))
      (true ack)
      (false (cap-supported-p ack)))))
