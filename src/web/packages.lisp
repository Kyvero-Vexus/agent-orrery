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
                #:ar-id #:ar-severity #:ar-title #:ar-fired-at
                ;; Audit trail (3l4)
                #:audit-trail-entry #:make-audit-trail-entry
                #:ate-seq #:ate-timestamp #:ate-category #:ate-severity
                #:ate-actor #:ate-summary #:ate-detail #:ate-hash
                ;; Session analytics (3l4)
                #:analytics-summary #:make-analytics-summary
                #:asm-total-sessions #:asm-avg-duration-s #:asm-median-tokens
                #:asm-avg-tokens-per-msg #:asm-total-cost-cents
                #:duration-bucket-record #:make-duration-bucket-record
                #:dbr-label #:dbr-count
                #:efficiency-record #:make-efficiency-record
                #:efr-session-id #:efr-tokens-per-message
                #:efr-tokens-per-minute #:efr-cost-per-1k)
  (:export
   ;; HTML generators (pure)
   #:render-page #:render-dashboard-html #:render-sessions-html
   #:render-session-detail-html #:render-cron-html #:render-alerts-html
   #:render-audit-trail-html #:render-analytics-html
   ;; JSON API (pure)
   #:dashboard-summary-json #:sessions-list-json #:health-json
   #:audit-trail-json #:analytics-json
   ;; Server (impure)
   #:*web-port* #:start-server #:stop-server
   ;; Fixture data for testing
   #:*fixture-sessions* #:*fixture-cron* #:*fixture-health* #:*fixture-alerts*
   #:*fixture-audit-trail* #:*fixture-analytics* #:*fixture-duration-buckets*
   #:*fixture-efficiency*))
