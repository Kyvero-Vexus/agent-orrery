;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; packages.lisp — Package definitions for Agent Orrery core
;;;

(defpackage #:orrery/domain
  (:use #:cl)
  (:export
   ;; Session
   #:session-record #:session-record-p #:copy-session-record
   #:make-session-record
   #:sr-id #:sr-agent-name #:sr-channel #:sr-status #:sr-model
   #:sr-created-at #:sr-updated-at #:sr-message-count
   #:sr-total-tokens #:sr-estimated-cost-cents
   ;; Cron
   #:cron-record #:cron-record-p #:copy-cron-record
   #:make-cron-record
   #:cr-name #:cr-kind #:cr-interval-s #:cr-status
   #:cr-last-run-at #:cr-next-run-at #:cr-run-count
   #:cr-last-error #:cr-description
   ;; Health
   #:health-record #:health-record-p #:copy-health-record
   #:make-health-record
   #:hr-component #:hr-status #:hr-message #:hr-checked-at #:hr-latency-ms
   ;; Usage
   #:usage-record #:usage-record-p #:copy-usage-record
   #:make-usage-record
   #:ur-model #:ur-period #:ur-timestamp
   #:ur-prompt-tokens #:ur-completion-tokens #:ur-total-tokens
   #:ur-estimated-cost-cents
   ;; Event
   #:event-record #:event-record-p #:copy-event-record
   #:make-event-record
   #:er-id #:er-kind #:er-source #:er-message #:er-timestamp #:er-metadata
   ;; Alert
   #:alert-record #:alert-record-p #:copy-alert-record
   #:make-alert-record
   #:ar-id #:ar-severity #:ar-title #:ar-message #:ar-source
   #:ar-fired-at #:ar-acknowledged-p #:ar-snoozed-until
   ;; Subagent
   #:subagent-record #:subagent-record-p #:copy-subagent-record
   #:make-subagent-record
   #:sar-id #:sar-parent-session #:sar-agent-name #:sar-status
   #:sar-started-at #:sar-finished-at #:sar-total-tokens #:sar-result
   ;; Message history entry
   #:history-entry #:history-entry-p #:copy-history-entry
   #:make-history-entry
   #:he-role #:he-content #:he-timestamp #:he-token-count
   ;; Capability descriptor
   #:adapter-capability #:adapter-capability-p #:copy-adapter-capability
   #:make-adapter-capability
   #:cap-name #:cap-description #:cap-supported-p))

(defpackage #:orrery/adapter
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:cron-record #:health-record
                #:usage-record #:event-record #:alert-record
                #:subagent-record #:history-entry #:adapter-capability)
  (:export
   ;; Core query protocol
   #:adapter-list-sessions
   #:adapter-session-history
   #:adapter-list-cron-jobs
   #:adapter-system-health
   #:adapter-usage-records
   #:adapter-tail-events
   #:adapter-list-alerts
   #:adapter-list-subagents
   ;; Command protocol
   #:adapter-trigger-cron
   #:adapter-pause-cron
   #:adapter-resume-cron
   #:adapter-acknowledge-alert
   #:adapter-snooze-alert
   ;; Capability introspection
   #:adapter-capabilities
   ;; Conditions
   #:adapter-error
   #:adapter-error-adapter
   #:adapter-error-operation
   #:adapter-not-supported
   #:adapter-not-found
   #:adapter-not-found-id))
