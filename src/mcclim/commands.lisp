;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; commands.lisp — McCLIM command tables for session/cron operations
;;; Bead: agent-orrery-eb0.5.2

(in-package #:orrery/mcclim)

;;; ─── Session Commands ───

(define-command (com-inspect-session :command-table orrery-dashboard
                                     :name t
                                     :menu t)
    ((session 'session-presentation :gesture :select))
  "Inspect a session record."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "Session: ~A~%" (sr-id session))
      (format pane "  Agent: ~A~%" (sr-agent-name session))
      (format pane "  Model: ~A~%" (sr-model session))
      (format pane "  Channel: ~A~%" (sr-channel session))
      (format pane "  Status: ~A~%" (sr-status session))
      (format pane "  Tokens: ~D~%" (sr-total-tokens session))
      (format pane "  Cost: ~D¢~%" (sr-estimated-cost-cents session)))))

(define-command (com-list-sessions :command-table orrery-dashboard
                                    :name "List Sessions"
                                    :menu t)
    ()
  "List all sessions to the interactor."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%=== Sessions (~D) ===~%" (length *fixture-sessions*))
      (dolist (s *fixture-sessions*)
        (format pane "  ~A  ~A  ~A  ~A~%"
                (sr-id s) (sr-agent-name s) (sr-model s) (sr-status s))))))

;;; ─── Cron Commands ───

(define-command (com-inspect-cron :command-table orrery-dashboard
                                   :name t
                                   :menu t)
    ((job 'cron-presentation :gesture :select))
  "Inspect a cron job."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "Cron Job: ~A~%" (cr-name job))
      (format pane "  Kind: ~A~%" (cr-kind job))
      (format pane "  Interval: ~Ds~%" (cr-interval-s job))
      (format pane "  Status: ~A~%" (cr-status job)))))

(define-command (com-trigger-cron :command-table orrery-dashboard
                                    :name "Trigger Cron"
                                    :menu t)
    ((job 'cron-presentation))
  "Trigger a cron job manually."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "Triggering ~A... (status: ~A)~%" (cr-name job) (cr-status job)))))

(define-command (com-pause-cron :command-table orrery-dashboard
                                  :name "Pause Cron"
                                  :menu t)
    ((job 'cron-presentation))
  "Pause a cron job."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "Pausing ~A... (status: ~A)~%" (cr-name job) (cr-status job)))))

(define-command (com-resume-cron :command-table orrery-dashboard
                                   :name "Resume Cron"
                                   :menu t)
    ((job 'cron-presentation))
  "Resume a paused cron job."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "Resuming ~A... (status: ~A)~%" (cr-name job) (cr-status job)))))

(define-command (com-list-cron :command-table orrery-dashboard
                                :name "List Cron"
                                :menu t)
    ()
  "List all cron jobs to the interactor."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%=== Cron Jobs (~D) ===~%" (length *fixture-cron*))
      (dolist (c *fixture-cron*)
        (format pane "  ~A  ~A  ~Ds  ~A~%"
                (cr-name c) (cr-kind c) (cr-interval-s c) (cr-status c))))))

;;; ─── Health Commands ───

(define-command (com-inspect-health :command-table orrery-dashboard
                                     :name t
                                     :menu t)
    ((component 'health-presentation :gesture :select))
  "Inspect a health component."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "Health: ~A~%" (hr-component component))
      (format pane "  Status: ~A~%" (hr-status component))
      (format pane "  Latency: ~Dms~%" (hr-latency-ms component)))))

;;; ─── Alert Commands ───

(define-command (com-inspect-alert :command-table orrery-dashboard
                                    :name t
                                    :menu t)
    ((alert 'alert-presentation :gesture :select))
  "Inspect an alert."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "Alert: ~A~%" (ar-id alert))
      (format pane "  Severity: ~A~%" (ar-severity alert))
      (format pane "  Title: ~A~%" (ar-title alert)))))

(define-command (com-list-alerts :command-table orrery-dashboard
                                  :name "List Alerts"
                                  :menu t)
    ()
  "List all alerts to the interactor."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%=== Alerts (~D) ===~%" (length *fixture-alerts*))
      (dolist (a *fixture-alerts*)
        (format pane "  ~A  ~A  ~A~%"
                (ar-id a) (ar-severity a) (ar-title a))))))

;;; ─── Dashboard Commands ───

(define-command (com-refresh :command-table orrery-dashboard
                              :name "Refresh"
                              :menu t
                              :keystroke (#\r :control))
    ()
  "Refresh all panes."
  (dolist (name '(sessions-pane cron-pane health-pane events-pane alerts-pane status-pane))
    (let ((pane (find-pane-named *application-frame* name)))
      (when pane
        (redisplay-frame-pane *application-frame* pane :force-p t)))))

(define-command (com-status :command-table orrery-dashboard
                             :name "Status"
                             :menu t)
    ()
  "Show dashboard status summary."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%=== Dashboard Status ===~%")
      (format pane "Sessions: ~D (active: ~D)~%"
              (length *fixture-sessions*)
              (count :active *fixture-sessions* :key #'sr-status))
      (format pane "Cron Jobs: ~D~%" (length *fixture-cron*))
      (format pane "Health: ~D (degraded: ~D)~%"
              (length *fixture-health*)
              (count :degraded *fixture-health* :key #'hr-status))
      (format pane "Alerts: ~D~%" (length *fixture-alerts*)))))
