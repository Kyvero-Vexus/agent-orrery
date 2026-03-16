;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; server.lisp — Hunchentoot web server + routes
;;; Bead: agent-orrery-eb0.4.1

(in-package #:orrery/web)

;;; ─── Fixture Data ───

(defvar *fixture-sessions*
  (list
   (make-session-record :id "sess-001" :agent-name "gensym" :channel "telegram"
                        :status :active :model "claude-opus-4" :total-tokens 15000
                        :estimated-cost-cents 450)
   (make-session-record :id "sess-002" :agent-name "semion" :channel "discord"
                        :status :idle :model "gpt-4" :total-tokens 8000
                        :estimated-cost-cents 240)
   (make-session-record :id "sess-003" :agent-name "herald" :channel "signal"
                        :status :closed :model "claude-sonnet" :total-tokens 3000
                        :estimated-cost-cents 90)))

(defvar *fixture-cron*
  (list
   (make-cron-record :name "watchdog" :kind :periodic :interval-s 3600 :status :active)
   (make-cron-record :name "sync" :kind :periodic :interval-s 900 :status :active)
   (make-cron-record :name "cleanup" :kind :daily :interval-s 86400 :status :idle)))

(defvar *fixture-health*
  (list
   (make-health-record :component "gateway" :status :healthy :latency-ms 12)
   (make-health-record :component "store" :status :healthy :latency-ms 5)
   (make-health-record :component "pipeline" :status :degraded :latency-ms 150)))

(defvar *fixture-alerts*
  (list
   (make-alert-record :id "alert-001" :severity :warning :title "High token usage on gensym"
                      :fired-at 1000)
   (make-alert-record :id "alert-002" :severity :info :title "Sync completed"
                      :fired-at 2000)))

;;; ─── Audit Trail Fixture Data (3l4) ───

(defvar *fixture-audit-trail*
  (list
   (make-audit-trail-entry :seq 1 :timestamp 1000 :category "session-lifecycle"
                           :severity "info" :actor "gensym"
                           :summary "Session sess-001 started"
                           :detail "Agent gensym connected via telegram"
                           :hash "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2")
   (make-audit-trail-entry :seq 2 :timestamp 1100 :category "model-routing"
                           :severity "info" :actor "pipeline"
                           :summary "Model selected: claude-opus-4"
                           :detail "Cost-optimal routing for sess-001"
                           :hash "b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a1")
   (make-audit-trail-entry :seq 3 :timestamp 1200 :category "cron-execution"
                           :severity "trace" :actor "watchdog"
                           :summary "Watchdog cron tick"
                           :detail "All health checks passed"
                           :hash "c3d4e5f6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a1b2")
   (make-audit-trail-entry :seq 4 :timestamp 1500 :category "alert-fired"
                           :severity "warning" :actor "monitor"
                           :summary "High token usage on gensym"
                           :detail "Token rate 500/min exceeds threshold 300/min"
                           :hash "d4e5f6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a1b2c3")
   (make-audit-trail-entry :seq 5 :timestamp 2000 :category "gate-decision"
                           :severity "critical" :actor "gate-engine"
                           :summary "Budget gate BLOCKED"
                           :detail "Daily spend 450c exceeds budget 400c"
                           :hash "e5f6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a3b4c5d6a7b8c9d0e1f2a1b2c3d4")))

;;; ─── Session Analytics Fixture Data (3l4) ───

(defvar *fixture-analytics*
  (make-analytics-summary :total-sessions 3
                          :avg-duration-s 240
                          :median-tokens 8000
                          :avg-tokens-per-msg 750
                          :total-cost-cents 780))

(defvar *fixture-duration-buckets*
  (list
   (make-duration-bucket-record :label "<1min" :count 0)
   (make-duration-bucket-record :label "1-5min" :count 2)
   (make-duration-bucket-record :label "5-15min" :count 1)
   (make-duration-bucket-record :label "15-60min" :count 0)
   (make-duration-bucket-record :label ">60min" :count 0)))

(defvar *fixture-efficiency*
  (list
   (make-efficiency-record :session-id "sess-001" :tokens-per-message 1500
                           :tokens-per-minute 2500 :cost-per-1k 30)
   (make-efficiency-record :session-id "sess-002" :tokens-per-message 800
                           :tokens-per-minute 1333 :cost-per-1k 30)
   (make-efficiency-record :session-id "sess-003" :tokens-per-message 600
                           :tokens-per-minute 1000 :cost-per-1k 30)))

;;; ─── Server State ───

(defvar *web-port* 7890)
(defvar *acceptor* nil)

;;; ─── Route Handlers ───

(defun handle-dashboard ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (render-dashboard-html *fixture-sessions* *fixture-cron* *fixture-health* *fixture-alerts*
                         *fixture-audit-trail* *fixture-analytics*))

(defun handle-sessions ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (render-sessions-html *fixture-sessions*))

(defun handle-session-detail ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (let* ((id (hunchentoot:parameter "id"))
         (session (find id *fixture-sessions* :key #'sr-id :test #'string=)))
    (render-session-detail-html session)))

(defun handle-cron ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (render-cron-html *fixture-cron*))

(defun handle-alerts ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (render-alerts-html *fixture-alerts*))

(defun handle-api-dashboard ()
  (setf (hunchentoot:content-type*) "application/json")
  (dashboard-summary-json *fixture-sessions* *fixture-cron* *fixture-health* *fixture-alerts*))

(defun handle-api-sessions ()
  (setf (hunchentoot:content-type*) "application/json")
  (sessions-list-json *fixture-sessions*))

(defun handle-api-health ()
  (setf (hunchentoot:content-type*) "application/json")
  (health-json *fixture-health*))

;;; ─── Audit Trail + Analytics Handlers (3l4) ───

(defun handle-audit-trail ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (render-audit-trail-html *fixture-audit-trail*))

(defun handle-analytics ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (render-analytics-html *fixture-analytics* *fixture-duration-buckets* *fixture-efficiency*))

(defun handle-api-audit-trail ()
  (setf (hunchentoot:content-type*) "application/json")
  (audit-trail-json *fixture-audit-trail*))

(defun handle-api-analytics ()
  (setf (hunchentoot:content-type*) "application/json")
  (analytics-json *fixture-analytics* *fixture-duration-buckets* *fixture-efficiency*))

;;; ─── Dispatcher ───

(defun orrery-dispatch (request)
  "Route requests to handlers."
  (let ((uri (hunchentoot:script-name request)))
    (cond
      ((string= uri "/") #'handle-dashboard)
      ((string= uri "/sessions") #'handle-sessions)
      ((and (>= (length uri) 10) (string= (subseq uri 0 10) "/sessions/"))
       ;; Extract session ID and store as parameter
       (setf (hunchentoot:aux-request-value 'session-id request)
             (subseq uri 10))
       (lambda ()
         (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
         (let* ((id (hunchentoot:aux-request-value 'session-id))
                (session (find id *fixture-sessions* :key #'sr-id :test #'string=)))
           (render-session-detail-html session))))
      ((string= uri "/cron") #'handle-cron)
      ((string= uri "/alerts") #'handle-alerts)
      ((string= uri "/audit-trail") #'handle-audit-trail)
      ((string= uri "/analytics") #'handle-analytics)
      ((string= uri "/api/dashboard") #'handle-api-dashboard)
      ((string= uri "/api/sessions") #'handle-api-sessions)
      ((string= uri "/api/health") #'handle-api-health)
      ((string= uri "/api/audit-trail") #'handle-api-audit-trail)
      ((string= uri "/api/analytics") #'handle-api-analytics)
      (t nil))))

;;; ─── Server Lifecycle ───

(defun start-server (&key (port *web-port*))
  "Start the web dashboard server."
  (when *acceptor* (stop-server))
  (setf *acceptor*
        (make-instance 'hunchentoot:easy-acceptor :port port))
  (push #'orrery-dispatch hunchentoot:*dispatch-table*)
  (hunchentoot:start *acceptor*)
  (format t "~&Orrery web dashboard started on port ~D~%" port)
  *acceptor*)

(defun stop-server ()
  "Stop the web dashboard server."
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf hunchentoot:*dispatch-table*
          (remove #'orrery-dispatch hunchentoot:*dispatch-table*))
    (setf *acceptor* nil)
    (format t "~&Orrery web dashboard stopped~%")))
