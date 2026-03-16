;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; frame.lisp — McCLIM dashboard frame and pane layout
;;; Bead: agent-orrery-eb0.5.1

(in-package #:orrery/mcclim)

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

(defvar *fixture-events*
  (list
   (make-event-record :id "ev-001" :kind :session :source "gensym" :timestamp 1000)
   (make-event-record :id "ev-002" :kind :cron :source "watchdog" :timestamp 2000)
   (make-event-record :id "ev-003" :kind :alert :source "pipeline" :timestamp 3000)))

(defvar *fixture-alerts*
  (list
   (make-alert-record :id "alert-001" :severity :warning
                      :title "High token usage on gensym" :fired-at 1000)
   (make-alert-record :id "alert-002" :severity :info
                      :title "Sync completed" :fired-at 2000)))

;;; ─── Presentation Types ───

(define-presentation-type session-presentation ())
(define-presentation-type cron-presentation ())
(define-presentation-type health-presentation ())
(define-presentation-type alert-presentation ())

;;; ─── Display Functions ───

(defun display-sessions (frame pane)
  "Display session list in the sessions pane."
  (declare (ignore frame))
  (formatting-table (pane)
    ;; Header
    (formatting-row (pane)
      (formatting-cell (pane) (write-string "ID" pane))
      (formatting-cell (pane) (write-string "Agent" pane))
      (formatting-cell (pane) (write-string "Model" pane))
      (formatting-cell (pane) (write-string "Status" pane))
      (formatting-cell (pane) (write-string "Tokens" pane))
      (formatting-cell (pane) (write-string "Cost" pane)))
    ;; Rows
    (dolist (s *fixture-sessions*)
      (formatting-row (pane)
        (formatting-cell (pane)
          (with-output-as-presentation (pane s 'session-presentation)
            (write-string (sr-id s) pane)))
        (formatting-cell (pane) (write-string (sr-agent-name s) pane))
        (formatting-cell (pane) (write-string (sr-model s) pane))
        (formatting-cell (pane) (format pane "~A" (sr-status s)))
        (formatting-cell (pane) (format pane "~D" (sr-total-tokens s)))
        (formatting-cell (pane) (format pane "~D¢" (sr-estimated-cost-cents s)))))))

(defun display-cron (frame pane)
  "Display cron jobs in the cron pane."
  (declare (ignore frame))
  (formatting-table (pane)
    (formatting-row (pane)
      (formatting-cell (pane) (write-string "Name" pane))
      (formatting-cell (pane) (write-string "Kind" pane))
      (formatting-cell (pane) (write-string "Interval" pane))
      (formatting-cell (pane) (write-string "Status" pane)))
    (dolist (c *fixture-cron*)
      (formatting-row (pane)
        (formatting-cell (pane)
          (with-output-as-presentation (pane c 'cron-presentation)
            (write-string (cr-name c) pane)))
        (formatting-cell (pane) (format pane "~A" (cr-kind c)))
        (formatting-cell (pane) (format pane "~Ds" (cr-interval-s c)))
        (formatting-cell (pane) (format pane "~A" (cr-status c)))))))

(defun display-health (frame pane)
  "Display health status in the health pane."
  (declare (ignore frame))
  (formatting-table (pane)
    (formatting-row (pane)
      (formatting-cell (pane) (write-string "Component" pane))
      (formatting-cell (pane) (write-string "Status" pane))
      (formatting-cell (pane) (write-string "Latency" pane)))
    (dolist (h *fixture-health*)
      (formatting-row (pane)
        (formatting-cell (pane)
          (with-output-as-presentation (pane h 'health-presentation)
            (write-string (hr-component h) pane)))
        (formatting-cell (pane) (format pane "~A" (hr-status h)))
        (formatting-cell (pane) (format pane "~Dms" (hr-latency-ms h)))))))

(defun display-events (frame pane)
  "Display events in the events pane."
  (declare (ignore frame))
  (formatting-table (pane)
    (formatting-row (pane)
      (formatting-cell (pane) (write-string "ID" pane))
      (formatting-cell (pane) (write-string "Kind" pane))
      (formatting-cell (pane) (write-string "Source" pane)))
    (dolist (e *fixture-events*)
      (formatting-row (pane)
        (formatting-cell (pane) (write-string (er-id e) pane))
        (formatting-cell (pane) (format pane "~A" (er-kind e)))
        (formatting-cell (pane) (write-string (er-source e) pane))))))

(defun display-alerts (frame pane)
  "Display alerts in the alerts pane."
  (declare (ignore frame))
  (formatting-table (pane)
    (formatting-row (pane)
      (formatting-cell (pane) (write-string "ID" pane))
      (formatting-cell (pane) (write-string "Severity" pane))
      (formatting-cell (pane) (write-string "Title" pane)))
    (dolist (a *fixture-alerts*)
      (formatting-row (pane)
        (formatting-cell (pane)
          (with-output-as-presentation (pane a 'alert-presentation)
            (write-string (ar-id a) pane)))
        (formatting-cell (pane) (format pane "~A" (ar-severity a)))
        (formatting-cell (pane) (write-string (ar-title a) pane))))))

(defun display-status (frame pane)
  "Display status bar content + keyboard discoverability hints."
  (declare (ignore frame))
  (format pane "Agent Orrery Dashboard | Sessions: ~D | Cron: ~D | Health: ~D | Alerts: ~D~%"
          (length *fixture-sessions*)
          (length *fixture-cron*)
          (length *fixture-health*)
          (length *fixture-alerts*))
  (format pane "Keys: ? help | C-n/C-p pane nav | C-r refresh | s status | q quit"))

;;; ─── Frame Definition ───

(define-application-frame orrery-dashboard ()
  ()
  (:panes
   (sessions-pane :application
                  :display-function #'display-sessions
                  :scroll-bars :vertical
                  :incremental-redisplay t)
   (cron-pane :application
              :display-function #'display-cron
              :scroll-bars :vertical
              :incremental-redisplay t)
   (health-pane :application
                :display-function #'display-health
                :scroll-bars :vertical
                :incremental-redisplay t)
   (events-pane :application
                :display-function #'display-events
                :scroll-bars :vertical
                :incremental-redisplay t)
   (alerts-pane :application
                :display-function #'display-alerts
                :scroll-bars :vertical
                :incremental-redisplay t)
   (status-pane :application
                :display-function #'display-status
                :max-height 30
                :scroll-bars nil)
   (interactor :interactor :scroll-bars :vertical))
  (:layouts
   (default
    (vertically ()
      (horizontally ()
        (2/5 (labelling (:label "Sessions") sessions-pane))
        (2/5 (labelling (:label "Cron Jobs") cron-pane))
        (1/5 (labelling (:label "Health") health-pane)))
      (horizontally ()
        (1/2 (labelling (:label "Events") events-pane))
        (1/2 (labelling (:label "Alerts") alerts-pane)))
      (1/10 status-pane)
      (1/5 interactor)))))
