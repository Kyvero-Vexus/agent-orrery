;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; packages.lisp — McCLIM dashboard packages
;;; Bead: agent-orrery-eb0.5.1

(defpackage #:orrery/mcclim
  (:use #:clim-lisp #:clim)
  (:import-from #:orrery/domain
                #:session-record #:make-session-record
                #:sr-id #:sr-agent-name #:sr-channel #:sr-status #:sr-model
                #:sr-total-tokens #:sr-estimated-cost-cents
                #:cron-record #:make-cron-record
                #:cr-name #:cr-kind #:cr-interval-s #:cr-status
                #:cr-run-count #:cr-last-error
                #:health-record #:make-health-record
                #:hr-component #:hr-status #:hr-latency-ms
                #:alert-record #:make-alert-record
                #:ar-id #:ar-severity #:ar-title #:ar-fired-at
                #:event-record #:make-event-record
                #:er-id #:er-kind #:er-source #:er-timestamp)
  (:export
   ;; Frame
   #:orrery-dashboard
   ;; Pane accessors
   #:sessions-pane #:cron-pane #:health-pane
   #:events-pane #:alerts-pane #:status-pane
   ;; Display functions (pure rendering)
   #:display-sessions #:display-cron
   #:display-health #:display-events
   #:display-alerts #:display-status
   ;; Fixture data
   #:*fixture-sessions* #:*fixture-cron*
   #:*fixture-health* #:*fixture-events*
   #:*fixture-alerts*
   ;; Presentation types
   #:session-presentation #:cron-presentation
   #:health-presentation #:alert-presentation
   ;; Commands (eb0.5.2)
   #:com-inspect-session #:com-list-sessions
   #:com-inspect-cron #:com-trigger-cron #:com-pause-cron #:com-resume-cron
   #:com-list-cron #:com-inspect-health
   #:com-inspect-alert #:com-list-alerts
   #:com-refresh #:com-status
   ;; Accessibility + keyboard parity (eb0.5.4)
   #:*focus-order* #:*focus-index* #:*keyboard-shortcuts*
   #:wrap-index #:focus-pane-by-name #:log-to-interactor
   #:com-help #:com-next-pane #:com-prev-pane #:com-quick-status #:com-quit
   ;; Inspectors (eb0.5.3)
   #:event-presentation
   #:com-session-detail #:com-event-detail
   #:com-alert-detail #:com-health-detail
   #:com-summary))
