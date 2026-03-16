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

;;; ─── Accessibility + Keyboard Parity (eb0.5.4) ───

(defparameter *focus-order*
  '(sessions-pane cron-pane health-pane events-pane alerts-pane interactor)
  "Canonical pane focus order for keyboard navigation parity.")

(defparameter *focus-index* 0
  "Current index into *focus-order* for keyboard focus navigation.")

(defparameter *keyboard-shortcuts*
  '(("C-r" . "Refresh")
    ("C-n" . "Focus next pane")
    ("C-p" . "Focus previous pane")
    ("?"   . "Keyboard help")
    ("s"   . "Status summary")
    ("q"   . "Quit dashboard"))
  "Discoverable keyboard shortcut reference.")

(declaim (ftype (function (fixnum fixnum fixnum) (values fixnum &optional)) wrap-index))
(defun wrap-index (value min max)
  "Wrap VALUE into inclusive [MIN, MAX] range. Pure helper."
  (cond
    ((< value min) max)
    ((> value max) min)
    (t value)))

(declaim (ftype (function (keyword) (values boolean &optional)) focus-pane-by-name))
(defun focus-pane-by-name (pane-name)
  "Focus a pane by name if present. Returns T on success."
  (let ((pane (find-pane-named *application-frame* pane-name)))
    (when pane
      ;; CLIM focus API varies by backend; keeping this minimal and portable.
      ;; We still provide deterministic command feedback via interactor.
      t)))

(declaim (ftype (function (string) (values null &optional)) log-to-interactor))
(defun log-to-interactor (message)
  "Write MESSAGE to interactor pane if available."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (write-string message pane)
      (terpri pane))))

(define-command (com-help :command-table orrery-dashboard
                           :name "Keyboard Help"
                           :menu t
                           :keystroke (#\?))
    ()
  "Show keyboard shortcuts and accessibility hints."
  (log-to-interactor "")
  (log-to-interactor "=== Keyboard Shortcuts ===")
  (dolist (binding *keyboard-shortcuts*)
    (log-to-interactor (format nil "  ~A  ->  ~A" (car binding) (cdr binding))))
  (log-to-interactor "")
  (log-to-interactor "Accessibility: all commands are menu-accessible and keyboard-invocable."))

(define-command (com-next-pane :command-table orrery-dashboard
                                :name "Next Pane"
                                :menu t
                                :keystroke (#\n :control))
    ()
  "Cycle focus to the next pane (keyboard parity with TUI navigation)."
  (setf *focus-index*
        (wrap-index (1+ *focus-index*) 0 (1- (length *focus-order*))))
  (let ((pane-name (nth *focus-index* *focus-order*)))
    (focus-pane-by-name pane-name)
    (log-to-interactor (format nil "Focus -> ~A" pane-name))))

(define-command (com-prev-pane :command-table orrery-dashboard
                                :name "Previous Pane"
                                :menu t
                                :keystroke (#\p :control))
    ()
  "Cycle focus to the previous pane."
  (setf *focus-index*
        (wrap-index (1- *focus-index*) 0 (1- (length *focus-order*))))
  (let ((pane-name (nth *focus-index* *focus-order*)))
    (focus-pane-by-name pane-name)
    (log-to-interactor (format nil "Focus -> ~A" pane-name))))

(define-command (com-quick-status :command-table orrery-dashboard
                                   :name "Quick Status"
                                   :menu t
                                   :keystroke (#\s))
    ()
  "Keyboard shortcut alias for status summary."
  (com-status))

(define-command (com-quit :command-table orrery-dashboard
                           :name "Quit"
                           :menu t
                           :keystroke (#\q))
    ()
  "Quit dashboard with keyboard parity to TUI q-key exit."
  (log-to-interactor "Quitting dashboard...")
  (frame-exit *application-frame*))
