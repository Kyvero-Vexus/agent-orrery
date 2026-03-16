;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; api.lisp — JSON API handlers (pure)
;;; Bead: agent-orrery-eb0.4.1

(in-package #:orrery/web)

(declaim (ftype (function (keyword list list) (values null &optional)) %assert-web-ui-contract))
(defun %assert-web-ui-contract (kind payload required-fields)
  "Validate payload against typed UI protocol contract.
Raises an error on contract mismatch." 
  (declare (type keyword kind)
           (type list payload required-fields)
           (optimize (safety 3)))
  (let* ((msg (orrery/adapter:make-ui-message* :web kind 0 0 payload))
         (contract (orrery/adapter:make-ui-contract
                    :surface :web
                    :kind kind
                    :required-fields required-fields
                    :schema-version "1.0"))
         (errors (orrery/adapter:validate-ui-message msg contract)))
    (when errors
      (error "Web UI protocol contract violation (~A): ~{~A~^, ~}" kind errors))))

(defun dashboard-summary-json (sessions cron-jobs health alerts)
  "Dashboard summary as JSON. Pure."
  (let ((payload (list (cons :session_count (length sessions))
                       (cons :active_count (count :active sessions :key #'sr-status))
                       (cons :cron_count (length cron-jobs))
                       (cons :health_count (length health))
                       (cons :alert_count (length alerts)))))
    (%assert-web-ui-contract :status payload '(:session_count :active_count :cron_count :health_count :alert_count))
    (format nil "{\"session_count\":~D,\"active_count\":~D,\"cron_count\":~D,\"health_count\":~D,\"alert_count\":~D}"
            (cdr (assoc :session_count payload))
            (cdr (assoc :active_count payload))
            (cdr (assoc :cron_count payload))
            (cdr (assoc :health_count payload))
            (cdr (assoc :alert_count payload)))))

(defun sessions-list-json (sessions)
  "Session list as JSON array. Pure."
  (%assert-web-ui-contract
   :session
   (list (cons :count (length sessions)))
   '(:count))
  (format nil "[~{~A~^,~}]"
          (mapcar (lambda (s)
                    (format nil "{\"id\":\"~A\",\"agent\":\"~A\",\"model\":\"~A\",\"status\":\"~A\",\"tokens\":~D,\"cost_cents\":~D}"
                            (sr-id s) (sr-agent-name s) (sr-model s)
                            (sr-status s) (sr-total-tokens s) (sr-estimated-cost-cents s)))
                  sessions)))

(defun health-json (health)
  "Health status as JSON array. Pure."
  (%assert-web-ui-contract :health (list (cons :count (length health))) '(:count))
  (format nil "[~{~A~^,~}]"
          (mapcar (lambda (h)
                    (format nil "{\"component\":\"~A\",\"status\":\"~A\",\"latency_ms\":~D}"
                            (hr-component h) (hr-status h) (hr-latency-ms h)))
                  health)))

;;; ─── Audit Trail JSON ───
;;; Bead: agent-orrery-3l4

(declaim (ftype (function (list) (values string &optional)) audit-trail-json))
(defun audit-trail-json (entries)
  "Audit trail entries as JSON array. Pure."
  (%assert-web-ui-contract :audit (list (cons :count (length entries))) '(:count))
  (format nil "[~{~A~^,~}]"
          (mapcar (lambda (e)
                    (format nil "{\"seq\":~D,\"category\":\"~A\",\"severity\":\"~A\",~
\"actor\":\"~A\",\"summary\":\"~A\",\"hash\":\"~A\"}"
                            (ate-seq e) (ate-category e) (ate-severity e)
                            (ate-actor e) (ate-summary e) (ate-hash e)))
                  entries)))

;;; ─── Session Analytics JSON ───
;;; Bead: agent-orrery-3l4

(declaim (ftype (function (t list list) (values string &optional)) analytics-json))
(defun analytics-json (summary duration-buckets efficiency-records)
  "Session analytics as JSON object. Pure."
  (%assert-web-ui-contract
   :analytics
   (list (cons :total_sessions (asm-total-sessions summary))
         (cons :duration_bucket_count (length duration-buckets))
         (cons :efficiency_count (length efficiency-records)))
   '(:total_sessions :duration_bucket_count :efficiency_count))
  (format nil "{\"summary\":{\"total_sessions\":~D,\"avg_duration_s\":~D,~
\"median_tokens\":~D,\"avg_tokens_per_msg\":~D,\"total_cost_cents\":~D},~
\"duration_buckets\":[~{~A~^,~}],\"efficiency\":[~{~A~^,~}]}"
          (asm-total-sessions summary) (asm-avg-duration-s summary)
          (asm-median-tokens summary) (asm-avg-tokens-per-msg summary)
          (asm-total-cost-cents summary)
          (mapcar (lambda (b)
                    (format nil "{\"label\":\"~A\",\"count\":~D}"
                            (dbr-label b) (dbr-count b)))
                  duration-buckets)
          (mapcar (lambda (e)
                    (format nil "{\"session_id\":\"~A\",\"tokens_per_message\":~D,~
\"tokens_per_minute\":~D,\"cost_per_1k\":~D}"
                            (efr-session-id e) (efr-tokens-per-message e)
                            (efr-tokens-per-minute e) (efr-cost-per-1k e)))
                  efficiency-records)))
