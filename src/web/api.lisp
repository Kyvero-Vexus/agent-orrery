;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; api.lisp — JSON API handlers (pure)
;;; Bead: agent-orrery-eb0.4.1

(in-package #:orrery/web)

(defun dashboard-summary-json (sessions cron-jobs health alerts)
  "Dashboard summary as JSON. Pure."
  (format nil "{\"session_count\":~D,\"active_count\":~D,\"cron_count\":~D,\"health_count\":~D,\"alert_count\":~D}"
          (length sessions)
          (count :active sessions :key #'sr-status)
          (length cron-jobs)
          (length health)
          (length alerts)))

(defun sessions-list-json (sessions)
  "Session list as JSON array. Pure."
  (format nil "[~{~A~^,~}]"
          (mapcar (lambda (s)
                    (format nil "{\"id\":\"~A\",\"agent\":\"~A\",\"model\":\"~A\",\"status\":\"~A\",\"tokens\":~D,\"cost_cents\":~D}"
                            (sr-id s) (sr-agent-name s) (sr-model s)
                            (sr-status s) (sr-total-tokens s) (sr-estimated-cost-cents s)))
                  sessions)))

(defun health-json (health)
  "Health status as JSON array. Pure."
  (format nil "[~{~A~^,~}]"
          (mapcar (lambda (h)
                    (format nil "{\"component\":\"~A\",\"status\":\"~A\",\"latency_ms\":~D}"
                            (hr-component h) (hr-status h) (hr-latency-ms h)))
                  health)))
