;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; packages.lisp — Web dashboard packages
;;; Bead: agent-orrery-eb0.4.1

(defpackage #:orrery/web
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:make-session-record
                #:sr-id #:sr-agent-name #:sr-channel #:sr-status #:sr-model
                #:sr-total-tokens #:sr-estimated-cost-cents
                #:cron-record #:make-cron-record
                #:cr-name #:cr-kind #:cr-interval-s #:cr-status
                #:health-record #:make-health-record
                #:hr-component #:hr-status #:hr-latency-ms
                #:alert-record #:make-alert-record
                #:ar-id #:ar-severity #:ar-title #:ar-fired-at)
  (:export
   ;; HTML generators (pure)
   #:render-page #:render-dashboard-html #:render-sessions-html
   #:render-session-detail-html #:render-cron-html #:render-alerts-html
   ;; JSON API (pure)
   #:dashboard-summary-json #:sessions-list-json #:health-json
   ;; Server (impure)
   #:*web-port* #:start-server #:stop-server
   ;; Fixture data for testing
   #:*fixture-sessions* #:*fixture-cron* #:*fixture-health* #:*fixture-alerts*))
