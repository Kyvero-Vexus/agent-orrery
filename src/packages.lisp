;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; packages.lisp — Package definitions for Agent Orrery core
;;;

(defpackage #:orrery/domain
  (:use #:cl)
  (:export
   ;; Session
   #:session-record #:session-record-p
   #:make-session-record
   #:sr-id #:sr-agent-name #:sr-channel #:sr-status #:sr-model
   #:sr-created-at #:sr-updated-at #:sr-message-count
   #:sr-total-tokens #:sr-estimated-cost-cents
   ;; Cron
   #:cron-record #:cron-record-p
   #:make-cron-record
   #:cr-name #:cr-kind #:cr-interval-s #:cr-status
   #:cr-last-run-at #:cr-next-run-at #:cr-run-count
   #:cr-last-error #:cr-description
   ;; Health
   #:health-record #:health-record-p
   #:make-health-record
   #:hr-component #:hr-status #:hr-message #:hr-checked-at #:hr-latency-ms
   ;; Usage
   #:usage-record #:usage-record-p
   #:make-usage-record
   #:ur-model #:ur-period #:ur-timestamp
   #:ur-prompt-tokens #:ur-completion-tokens #:ur-total-tokens
   #:ur-estimated-cost-cents
   ;; Event
   #:event-record #:event-record-p
   #:make-event-record
   #:er-id #:er-kind #:er-source #:er-message #:er-timestamp #:er-metadata
   ;; Alert
   #:alert-record #:alert-record-p
   #:make-alert-record
   #:ar-id #:ar-severity #:ar-title #:ar-message #:ar-source
   #:ar-fired-at #:ar-acknowledged-p #:ar-snoozed-until
   ;; Subagent
   #:subagent-record #:subagent-record-p
   #:make-subagent-record
   #:sar-id #:sar-parent-session #:sar-agent-name #:sar-status
   #:sar-started-at #:sar-finished-at #:sar-total-tokens #:sar-result))

(defpackage #:orrery/adapter
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:cron-record #:health-record
                #:usage-record #:event-record #:alert-record #:subagent-record)
  (:export
   #:adapter-list-sessions
   #:adapter-session-history
   #:adapter-list-cron-jobs
   #:adapter-trigger-cron
   #:adapter-system-health
   #:adapter-usage-records
   #:adapter-tail-events
   #:adapter-list-alerts
   #:adapter-acknowledge-alert
   #:adapter-list-subagents))
