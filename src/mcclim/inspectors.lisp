;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; inspectors.lisp — McCLIM inspectors for sessions/events/alerts
;;; Bead: agent-orrery-eb0.5.3
;;;
;;; Rich inspection views: detail panes, formatted output, cross-references.

(in-package #:orrery/mcclim)

;;; ─── Session Inspector ───

(define-presentation-method present (object (type session-presentation)
                                            stream (view textual-view) &key)
  "Rich presentation for session records."
  (format stream "~A (~A)" (sr-id object) (sr-agent-name object)))

(define-command (com-session-detail :command-table orrery-dashboard
                                     :name "Session Detail"
                                     :menu t)
    ((session 'session-presentation))
  "Show full session detail in the interactor."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%╔══ Session Inspector ══╗~%")
      (format pane "║ ID:      ~A~%" (sr-id session))
      (format pane "║ Agent:   ~A~%" (sr-agent-name session))
      (format pane "║ Model:   ~A~%" (sr-model session))
      (format pane "║ Channel: ~A~%" (sr-channel session))
      (format pane "║ Status:  ~A~%" (sr-status session))
      (format pane "║ Tokens:  ~:D~%" (sr-total-tokens session))
      (format pane "║ Cost:    ~D¢ ($~,2F)~%"
              (sr-estimated-cost-cents session)
              (/ (sr-estimated-cost-cents session) 100.0))
      (format pane "╚════════════════════════╝~%"))))

;;; ─── Event Inspector ───

(define-presentation-type event-presentation ())

(define-presentation-method present (object (type event-presentation)
                                            stream (view textual-view) &key)
  "Rich presentation for event records."
  (format stream "~A [~A]" (er-id object) (er-kind object)))

(define-command (com-event-detail :command-table orrery-dashboard
                                    :name "Event Detail"
                                    :menu t)
    ()
  "Show event log details."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%╔══ Event Inspector ══╗~%")
      (dolist (e *fixture-events*)
        (format pane "║ ~A  kind:~A  src:~A  t:~D~%"
                (er-id e) (er-kind e) (er-source e) (er-timestamp e)))
      (format pane "╚══════════════════════╝~%"))))

;;; ─── Alert Inspector ───

(define-presentation-method present (object (type alert-presentation)
                                            stream (view textual-view) &key)
  "Rich presentation for alert records."
  (format stream "~A [~A] ~A" (ar-id object) (ar-severity object) (ar-title object)))

(define-command (com-alert-detail :command-table orrery-dashboard
                                    :name "Alert Detail"
                                    :menu t)
    ((alert 'alert-presentation))
  "Show full alert detail."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%╔══ Alert Inspector ══╗~%")
      (format pane "║ ID:       ~A~%" (ar-id alert))
      (format pane "║ Severity: ~A~%" (ar-severity alert))
      (format pane "║ Title:    ~A~%" (ar-title alert))
      (format pane "║ Fired:    ~D~%" (ar-fired-at alert))
      (format pane "╚═══════════════════════╝~%"))))

;;; ─── Health Inspector ───

(define-presentation-method present (object (type health-presentation)
                                            stream (view textual-view) &key)
  "Rich presentation for health records."
  (format stream "~A [~A ~Dms]" (hr-component object) (hr-status object) (hr-latency-ms object)))

(define-command (com-health-detail :command-table orrery-dashboard
                                     :name "Health Detail"
                                     :menu t)
    ((component 'health-presentation))
  "Show full health component detail."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%╔══ Health Inspector ══╗~%")
      (format pane "║ Component: ~A~%" (hr-component component))
      (format pane "║ Status:    ~A~%" (hr-status component))
      (format pane "║ Latency:   ~Dms~%" (hr-latency-ms component))
      (format pane "║ Ok?:       ~A~%"
              (if (eq (hr-status component) :healthy) "YES" "NO"))
      (format pane "╚════════════════════════╝~%"))))

;;; ─── Cross-Reference Summary ───

(define-command (com-summary :command-table orrery-dashboard
                              :name "Summary"
                              :menu t)
    ()
  "Show cross-referenced summary of all entities."
  (let ((pane (find-pane-named *application-frame* 'interactor)))
    (when pane
      (fresh-line pane)
      (format pane "~%╔══ Agent Orrery Summary ══╗~%")
      (format pane "║ Sessions: ~D~%" (length *fixture-sessions*))
      (format pane "║   Active: ~D~%" (count :active *fixture-sessions* :key #'sr-status))
      (format pane "║   Idle:   ~D~%" (count :idle *fixture-sessions* :key #'sr-status))
      (format pane "║   Closed: ~D~%" (count :closed *fixture-sessions* :key #'sr-status))
      (format pane "║ Cron:     ~D~%" (length *fixture-cron*))
      (format pane "║ Health:   ~D (~D degraded)~%"
              (length *fixture-health*)
              (count :degraded *fixture-health* :key #'hr-status))
      (format pane "║ Events:   ~D~%" (length *fixture-events*))
      (format pane "║ Alerts:   ~D (~D warning)~%"
              (length *fixture-alerts*)
              (count :warning *fixture-alerts* :key #'ar-severity))
      (format pane "║ Total cost: ~D¢~%"
              (reduce #'+ *fixture-sessions* :key #'sr-estimated-cost-cents))
      (format pane "╚═══════════════════════════╝~%"))))
