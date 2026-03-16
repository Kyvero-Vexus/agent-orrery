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

;;; ─── Server State ───

(defvar *web-port* 7890)
(defvar *acceptor* nil)

;;; ─── Route Handlers ───

(defun handle-dashboard ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (render-dashboard-html *fixture-sessions* *fixture-cron* *fixture-health* *fixture-alerts*))

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
      ((string= uri "/api/dashboard") #'handle-api-dashboard)
      ((string= uri "/api/sessions") #'handle-api-sessions)
      ((string= uri "/api/health") #'handle-api-health)
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
