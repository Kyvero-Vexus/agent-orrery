;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; generic-starter-kit-tests.lisp — Tests for generic adapter starter kit
;;; Bead: agent-orrery-eb0.6.2

(in-package #:orrery/harness-tests)

(define-test generic-starter-kit-tests)

(defun %mk-ht (&rest kv)
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do (setf (gethash k ht) v))
    ht))

(defun %starter-mock-request-fn (table)
  (lambda (adapter method path &key payload)
    (declare (ignore adapter payload))
    (gethash (list method path) table)))

(defun %make-starter-adapter ()
  (let ((table (make-hash-table :test 'equal)))
    ;; sessions
    (setf (gethash (list :get "/sessions") table)
          (vector (%mk-ht "id" "sess-1" "agent" "ops" "channel" "webchat"
                          "status" "active" "model" "gpt" "created_at" 10
                          "updated_at" 20 "message_count" 3 "total_tokens" 100
                          "estimated_cost_cents" 2)))
    ;; history
    (setf (gethash (list :get "/sessions/sess-1/history") table)
          (vector (%mk-ht "role" "user" "content" "hi" "timestamp" 11 "token_count" 5)))
    ;; cron jobs
    (setf (gethash (list :get "/cron/jobs") table)
          (vector (%mk-ht "name" "backup" "kind" "periodic" "interval_s" 60
                          "status" "active" "run_count" 4)))
    ;; health
    (setf (gethash (list :get "/health") table)
          (vector (%mk-ht "component" "gateway" "status" "ok" "message" "ready"
                          "checked_at" 1 "latency_ms" 2)))
    ;; usage
    (setf (gethash (list :get "/usage") table)
          (vector (%mk-ht "model" "gpt" "period" "hourly" "timestamp" 1
                          "prompt_tokens" 10 "completion_tokens" 5 "total_tokens" 15
                          "estimated_cost_cents" 1)))
    ;; events
    (setf (gethash (list :get "/events") table)
          (vector (%mk-ht "id" "e1" "kind" "info" "source" "adapter" "message" "ok" "timestamp" 12)))
    ;; alerts
    (setf (gethash (list :get "/alerts") table)
          (vector (%mk-ht "id" "a1" "severity" "warning" "title" "A" "message" "m"
                          "source" "sys" "fired_at" 30 "acknowledged" nil)))
    ;; subagents
    (setf (gethash (list :get "/subagents") table)
          (vector (%mk-ht "id" "sub-1" "parent_session" "sess-1" "agent_name" "worker"
                          "status" "running" "started_at" 1 "total_tokens" 99)))
    ;; mutating command endpoints
    (setf (gethash (list :post "/cron/jobs/backup/run") table) t)
    (setf (gethash (list :post "/cron/jobs/backup/pause") table) t)
    (setf (gethash (list :post "/cron/jobs/backup/resume") table) t)
    (setf (gethash (list :post "/alerts/a1/ack") table) t)
    (setf (gethash (list :post "/alerts/a1/snooze") table) t)

    (orrery/adapter:make-reference-starter-adapter
     :adapter-name "starter"
     :base-url "http://mock"
     :request-fn (%starter-mock-request-fn table))))

(define-test (generic-starter-kit-tests constructor-and-specs)
  (let ((adapter (%make-starter-adapter)))
    (is string= "starter" (orrery/adapter:starter-adapter-name adapter))
    (true (orrery/adapter:find-starter-endpoint adapter :sessions))
    (true (orrery/adapter:find-starter-endpoint adapter :history))))

(define-test (generic-starter-kit-tests query-surfaces)
  (let ((adapter (%make-starter-adapter)))
    (let ((sessions (orrery/adapter:adapter-list-sessions adapter)))
      (is = 1 (length sessions))
      (is string= "sess-1" (sr-id (first sessions))))
    (let ((hist (orrery/adapter:adapter-session-history adapter "sess-1")))
      (is = 1 (length hist))
      (is eq :user (he-role (first hist))))
    (is = 1 (length (orrery/adapter:adapter-list-cron-jobs adapter)))
    (is = 1 (length (orrery/adapter:adapter-system-health adapter)))
    (is = 1 (length (orrery/adapter:adapter-usage-records adapter :period :hourly)))
    (is = 1 (length (orrery/adapter:adapter-tail-events adapter :since 0 :limit 50)))
    (is = 1 (length (orrery/adapter:adapter-list-alerts adapter)))
    (is = 1 (length (orrery/adapter:adapter-list-subagents adapter)))))

(define-test (generic-starter-kit-tests command-surfaces)
  (let ((adapter (%make-starter-adapter)))
    (true (orrery/adapter:adapter-trigger-cron adapter "backup"))
    (true (orrery/adapter:adapter-pause-cron adapter "backup"))
    (true (orrery/adapter:adapter-resume-cron adapter "backup"))
    (true (orrery/adapter:adapter-acknowledge-alert adapter "a1"))
    (true (orrery/adapter:adapter-snooze-alert adapter "a1" 60))))

(define-test (generic-starter-kit-tests capabilities-surface)
  (let* ((adapter (%make-starter-adapter))
         (caps (orrery/adapter:adapter-capabilities adapter)))
    (true (> (length caps) 0))
    (true (find "session-history" caps :key #'cap-name :test #'string=))
    (true (find "trigger-cron" caps :key #'cap-name :test #'string=))))

(define-test (generic-starter-kit-tests unsupported-operation-raises)
  (let ((adapter (%make-starter-adapter)))
    ;; disable alerts endpoint to simulate partial runtime
    (remhash :alerts (orrery/adapter:starter-endpoint-table adapter))
    (fail (orrery/adapter:adapter-list-alerts adapter) orrery/adapter:adapter-not-supported)))
