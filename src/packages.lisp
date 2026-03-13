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

(defpackage #:orrery/adapter/openclaw
  (:use #:cl)
  (:import-from #:orrery/domain
                #:make-session-record
                #:make-history-entry
                #:make-cron-record
                #:make-health-record
                #:make-usage-record
                #:make-event-record
                #:make-alert-record
                #:make-subagent-record
                #:make-adapter-capability)
  (:import-from #:orrery/adapter
                #:adapter-list-sessions
                #:adapter-session-history
                #:adapter-list-cron-jobs
                #:adapter-trigger-cron
                #:adapter-pause-cron
                #:adapter-resume-cron
                #:adapter-system-health
                #:adapter-usage-records
                #:adapter-tail-events
                #:adapter-list-alerts
                #:adapter-acknowledge-alert
                #:adapter-snooze-alert
                #:adapter-list-subagents
                #:adapter-capabilities
                #:adapter-error
                #:adapter-not-supported
                #:adapter-not-found)
  (:export
   #:openclaw-adapter
   #:make-openclaw-adapter
   #:openclaw-base-url
   #:openclaw-api-token
   #:openclaw-timeout-s
   #:%openclaw-request))

(defpackage #:orrery/coalton/core
  (:use #:coalton #:coalton-prelude)
  (:export
   #:normalize-status-code
   #:estimate-cost-cents))

(defpackage #:orrery/pipeline
  (:use #:cl)
  (:import-from #:orrery/domain
                #:event-record #:event-record-p
                #:usage-record #:make-usage-record
                #:alert-record #:make-alert-record
                #:er-kind #:er-source #:er-message #:er-timestamp #:er-metadata
                #:ur-model #:ur-total-tokens #:ur-estimated-cost-cents
                #:ar-id #:ar-severity #:ar-title #:ar-message #:ar-source #:ar-fired-at
                #:ar-acknowledged-p #:ar-snoozed-until)
  (:import-from #:orrery/coalton/core
                #:estimate-cost-cents)
  (:export
   #:projection-state #:projection-state-p #:make-projection-state
   #:ps-usage #:ps-activity #:ps-alerts
   #:reduce-event #:ingest-events
   #:project-usage-summary #:project-activity-feed #:project-alert-state))

(defpackage #:orrery/store
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:cron-record #:health-record
                #:usage-record #:event-record #:alert-record #:subagent-record)
  (:import-from #:orrery/adapter
                #:adapter-list-sessions #:adapter-list-cron-jobs #:adapter-system-health
                #:adapter-usage-records #:adapter-tail-events #:adapter-list-alerts
                #:adapter-list-subagents)
  (:import-from #:orrery/pipeline
                #:ingest-events #:project-usage-summary #:project-alert-state)
  (:export
   #:sync-store #:sync-store-p #:make-sync-store
   #:ss-sessions #:ss-cron-jobs #:ss-health #:ss-usage #:ss-events #:ss-alerts #:ss-subagents
   #:ss-last-sync-at #:ss-sync-token
   #:snapshot-from-adapter #:apply-incremental-events #:replay-events #:store->plist))
