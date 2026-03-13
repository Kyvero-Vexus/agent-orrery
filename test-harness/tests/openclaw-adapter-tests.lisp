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

(defun %ok-vector-response (&rest objs)
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash "ok" ht) t
          (gethash "result" ht) (coerce objs 'vector))
    ht))

(defun %ok-object-response (obj)
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash "ok" ht) t
          (gethash "result" ht) obj)
    ht))

(defun %api-error (code)
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash "ok" ht) nil
          (gethash "error_code" ht) code)
    ht))

(defmethod %openclaw-request ((adapter mock-openclaw-adapter) method path &key payload)
  (declare (ignore payload))
  (or (gethash (list method path) (mock-responses adapter))
      (error "No mock response for ~A ~A" method path)))

(defun make-mock-adapter ()
  (let ((tbl (%make-response-table)))
    ;; /sessions
    (%set-response tbl :get "/sessions"
                   (%ok-vector-response
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

    ;; /sessions/<id>/history
    (%set-response tbl :get "/sessions/sess-1/history"
                   (%ok-vector-response
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

    ;; /cron/jobs
    (%set-response tbl :get "/cron/jobs"
                   (%ok-vector-response
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

    ;; cron command endpoints
    (%set-response tbl :post "/cron/jobs/backup/run" (%ok-vector-response))
    (%set-response tbl :post "/cron/jobs/backup/pause" (%ok-vector-response))
    (%set-response tbl :post "/cron/jobs/backup/resume" (%ok-vector-response))

    ;; /health (result object form)
    (%set-response tbl :get "/health"
                   (%ok-object-response
                    (let ((h (make-hash-table :test 'equal)))
                      (setf (gethash "component" h) "gateway"
                            (gethash "status" h) "ok"
                            (gethash "message" h) "ready"
                            (gethash "checked_at" h) 999
                            (gethash "latency_ms" h) 12)
                      h)))

    ;; /usage
    (%set-response tbl :get "/usage"
                   (%ok-vector-response
                    (let ((u (make-hash-table :test 'equal)))
                      (setf (gethash "model" u) "gpt-4"
                            (gethash "period" u) "hourly"
                            (gethash "timestamp" u) 1000
                            (gethash "prompt_tokens" u) 100
                            (gethash "completion_tokens" u) 50
                            (gethash "total_tokens" u) 150
                            (gethash "estimated_cost_cents" u) 3)
                      u)))

    ;; /events
    (%set-response tbl :get "/events"
                   (%ok-vector-response
                    (let ((e (make-hash-table :test 'equal)))
                      (setf (gethash "id" e) "evt-1"
                            (gethash "kind" e) "warning"
                            (gethash "source" e) "system"
                            (gethash "message" e) "degraded"
                            (gethash "timestamp" e) 2000)
                      e)))

    ;; /alerts + commands
    (%set-response tbl :get "/alerts"
                   (%ok-vector-response
                    (let ((a (make-hash-table :test 'equal)))
                      (setf (gethash "id" a) "alert-1"
                            (gethash "severity" a) "critical"
                            (gethash "title" a) "CPU"
                            (gethash "message" a) "CPU high"
                            (gethash "source" a) "system"
                            (gethash "fired_at" a) 3000
                            (gethash "acknowledged" a) nil)
                      a)))
    (%set-response tbl :post "/alerts/alert-1/ack" (%ok-vector-response))
    (%set-response tbl :post "/alerts/alert-1/snooze" (%ok-vector-response))

    ;; /subagents
    (%set-response tbl :get "/subagents"
                   (%ok-vector-response
                    (let ((s (make-hash-table :test 'equal)))
                      (setf (gethash "id" s) "sub-1"
                            (gethash "parent_session" s) "sess-1"
                            (gethash "agent_name" s) "worker"
                            (gethash "status" s) "running"
                            (gethash "started_at" s) 4000
                            (gethash "total_tokens" s) 99)
                      s)))

    ;; Explicit API-level errors for mapping tests
    (%set-response tbl :get "/sessions/missing/history" (%api-error 404))
    (%set-response tbl :get "/alerts-unsupported" (%api-error 501))

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

(define-test (openclaw-adapter-tests session-history-not-found-maps)
  (let ((a (make-mock-adapter)))
    (fail (adapter-session-history a "missing") adapter-not-found)))

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

(define-test (openclaw-adapter-tests usage-events-alerts-subagents-normalization)
  (let ((a (make-mock-adapter)))
    (let ((usage (adapter-usage-records a :period :hourly)))
      (is = 1 (length usage))
      (true (usage-record-p (first usage))))
    (let ((events (adapter-tail-events a :since 0 :limit 50)))
      (is = 1 (length events))
      (true (event-record-p (first events))))
    (let ((alerts (adapter-list-alerts a)))
      (is = 1 (length alerts))
      (true (alert-record-p (first alerts))))
    (let ((subs (adapter-list-subagents a)))
      (is = 1 (length subs))
      (true (subagent-record-p (first subs))))))

(define-test (openclaw-adapter-tests alert-commands-supported)
  (let ((a (make-mock-adapter)))
    (true (adapter-acknowledge-alert a "alert-1"))
    (true (adapter-snooze-alert a "alert-1" 60))))

(define-test (openclaw-adapter-tests cron-commands-supported)
  (let ((a (make-mock-adapter)))
    (true (adapter-trigger-cron a "backup"))
    (true (adapter-pause-cron a "backup"))
    (true (adapter-resume-cron a "backup"))))

(define-test (openclaw-adapter-tests capabilities-surface-matches-implemented)
  (let ((caps (adapter-capabilities (make-mock-adapter))))
    (true (plusp (length caps)))
    (dolist (name '("trigger-cron" "pause-cron" "resume-cron"
                    "session-history" "acknowledge-alert" "snooze-alert"
                    "usage" "events" "subagents"))
      (let ((cap (find name caps :key #'cap-name :test #'string=)))
        (true cap)
        (true (cap-supported-p cap))))))

;;; ------------------------------------------------------------
;;; Live integration (optional)
;;; ------------------------------------------------------------
;;;
;;; If ORRERY_OPENCLAW_BASE_URL is set, run lightweight live checks.
;;; Otherwise test passes vacuously.

(defun %live-base-url ()
  #+sbcl (sb-ext:posix-getenv "ORRERY_OPENCLAW_BASE_URL")
  #-sbcl nil)

(define-test (openclaw-adapter-tests live-integration-optional)
  (let ((base (%live-base-url)))
    (if (or (null base) (string= base ""))
        (true t) ; no live endpoint configured in CI/local
        (let* ((token #+sbcl (sb-ext:posix-getenv "ORRERY_OPENCLAW_TOKEN")
                      #-sbcl nil)
               (a (make-openclaw-adapter :base-url base :api-token token :timeout-s 5)))
          ;; Should at least be callable; endpoint shape varies by deployment.
          ;; We allow either success or adapter-not-supported for non-core surfaces.
          (finish (adapter-system-health a))
          (finish (adapter-list-sessions a))
          (finish (adapter-list-cron-jobs a))))))
