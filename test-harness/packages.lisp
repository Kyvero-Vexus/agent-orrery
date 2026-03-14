;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; packages.lisp — Package definitions for the test harness
;;;

(defpackage #:orrery/harness
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:make-session-record #:session-record-p
                #:sr-id #:sr-agent-name #:sr-channel #:sr-status #:sr-model
                #:sr-created-at #:sr-updated-at #:sr-message-count
                #:sr-total-tokens #:sr-estimated-cost-cents
                #:cron-record #:make-cron-record #:cron-record-p
                #:cr-name #:cr-kind #:cr-interval-s #:cr-status
                #:cr-last-run-at #:cr-next-run-at #:cr-run-count
                #:cr-last-error #:cr-description
                #:health-record #:make-health-record #:health-record-p
                #:hr-component #:hr-status #:hr-message #:hr-checked-at #:hr-latency-ms
                #:usage-record #:make-usage-record #:usage-record-p
                #:ur-model #:ur-period #:ur-timestamp
                #:ur-prompt-tokens #:ur-completion-tokens #:ur-total-tokens
                #:ur-estimated-cost-cents
                #:event-record #:make-event-record #:event-record-p
                #:er-id #:er-kind #:er-source #:er-message #:er-timestamp #:er-metadata
                #:alert-record #:make-alert-record #:alert-record-p
                #:ar-id #:ar-severity #:ar-title #:ar-message #:ar-source
                #:ar-fired-at #:ar-acknowledged-p #:ar-snoozed-until
                #:subagent-record #:make-subagent-record #:subagent-record-p
                #:sar-id #:sar-parent-session #:sar-agent-name #:sar-status
                #:sar-started-at #:sar-finished-at #:sar-total-tokens #:sar-result
                #:history-entry #:make-history-entry #:history-entry-p
                #:he-role #:he-content #:he-timestamp #:he-token-count
                #:adapter-capability #:make-adapter-capability #:adapter-capability-p
                #:cap-name #:cap-description #:cap-supported-p)
  (:import-from #:orrery/adapter
                #:adapter-list-sessions #:adapter-session-history
                #:adapter-list-cron-jobs #:adapter-trigger-cron
                #:adapter-pause-cron #:adapter-resume-cron
                #:adapter-system-health #:adapter-usage-records
                #:adapter-tail-events #:adapter-list-alerts
                #:adapter-acknowledge-alert #:adapter-snooze-alert
                #:adapter-list-subagents #:adapter-capabilities
                #:adapter-error #:adapter-not-supported #:adapter-not-found)
  (:import-from #:orrery/adapter/openclaw
                #:openclaw-adapter #:make-openclaw-adapter
                #:openclaw-base-url #:openclaw-api-token #:openclaw-timeout-s
                #:openclaw-transport-error #:openclaw-decode-error
                #:openclaw-fetch-sessions #:openclaw-fetch-cron-jobs #:openclaw-fetch-health
                #:openclaw-decode-sessions #:openclaw-decode-cron-jobs #:openclaw-decode-health
                #:openclaw-live-contract-probe
                #:probe-report #:probe-report-p #:probe-report-overall-ok-p #:probe-report-results
                #:probe-endpoint-result #:probe-endpoint-result-endpoint #:probe-endpoint-result-ok-p
                #:probe-endpoint-result-mismatches
                #:probe-mismatch #:probe-mismatch-category
                #:%openclaw-request)
  (:import-from #:orrery/coalton/core
                #:normalize-status-code #:estimate-cost-cents)
  (:export
   ;; Clock
   #:fixture-clock #:make-fixture-clock #:clock-now #:clock-advance! #:clock-set!
   ;; Timeline
   #:timeline #:make-timeline #:timeline-schedule #:timeline-run-until!
   #:timeline-pending-count
   ;; Generators
   #:generate-sessions #:generate-cron-jobs #:generate-health-checks
   #:generate-usage-records #:generate-events #:generate-alerts
   #:generate-subagent-runs
   ;; Fixture adapter
   #:fixture-adapter #:make-fixture-adapter
   #:fixture-adapter-clock #:fixture-adapter-timeline
   #:fixture-sessions #:fixture-cron-jobs #:fixture-health
   #:fixture-usage #:fixture-events #:fixture-alerts #:fixture-subagents
   ;; Conformance testing
   #:run-adapter-conformance
   #:run-adapter-conformance-suite))

(defpackage #:orrery/harness-tests
  (:use #:cl #:parachute)
  (:import-from #:orrery/harness
                #:fixture-clock #:make-fixture-clock
                #:clock-now #:clock-advance! #:clock-set!
                #:timeline #:make-timeline #:timeline-schedule
                #:timeline-run-until! #:timeline-pending-count
                #:generate-sessions #:generate-cron-jobs
                #:generate-health-checks #:generate-usage-records
                #:generate-events #:generate-alerts #:generate-subagent-runs
                #:fixture-adapter #:make-fixture-adapter
                #:fixture-sessions #:fixture-cron-jobs #:fixture-health
                #:fixture-usage #:fixture-events #:fixture-alerts
                #:fixture-subagents
                #:fixture-adapter-clock #:fixture-adapter-timeline
                #:run-adapter-conformance
                #:run-adapter-conformance-suite)
  (:import-from #:orrery/domain
                #:session-record #:session-record-p
                #:sr-id #:sr-agent-name #:sr-status
                #:sr-total-tokens #:sr-message-count
                #:cron-record #:cron-record-p
                #:cr-name #:cr-kind #:cr-status #:cr-run-count
                #:health-record #:health-record-p
                #:hr-component #:hr-status
                #:usage-record #:usage-record-p
                #:ur-model #:ur-period #:ur-timestamp #:ur-total-tokens
                #:event-record #:event-record-p
                #:er-id #:er-kind #:er-timestamp
                #:alert-record #:alert-record-p
                #:ar-id #:ar-acknowledged-p #:ar-severity #:ar-snoozed-until
                #:subagent-record #:subagent-record-p
                #:sar-id #:sar-status
                #:make-session-record #:make-event-record #:make-alert-record
                #:history-entry #:history-entry-p
                #:he-role #:he-content #:he-timestamp #:he-token-count
                #:adapter-capability #:adapter-capability-p
                #:cap-name #:cap-supported-p)
  (:import-from #:orrery/adapter
                #:adapter-list-sessions #:adapter-session-history
                #:adapter-list-cron-jobs #:adapter-trigger-cron
                #:adapter-pause-cron #:adapter-resume-cron
                #:adapter-system-health #:adapter-usage-records
                #:adapter-tail-events #:adapter-list-alerts
                #:adapter-acknowledge-alert #:adapter-snooze-alert
                #:adapter-list-subagents #:adapter-capabilities
                #:adapter-error #:adapter-not-supported #:adapter-not-found)
  (:import-from #:orrery/adapter/openclaw
                #:openclaw-adapter #:make-openclaw-adapter
                #:openclaw-base-url #:openclaw-api-token #:openclaw-timeout-s
                #:openclaw-transport-error #:openclaw-decode-error
                #:openclaw-fetch-sessions #:openclaw-fetch-cron-jobs #:openclaw-fetch-health
                #:openclaw-decode-sessions #:openclaw-decode-cron-jobs #:openclaw-decode-health
                #:openclaw-live-contract-probe
                #:probe-report #:probe-report-p #:probe-report-overall-ok-p #:probe-report-results
                #:probe-endpoint-result #:probe-endpoint-result-endpoint #:probe-endpoint-result-ok-p
                #:probe-endpoint-result-mismatches
                #:probe-mismatch #:probe-mismatch-category
                #:%openclaw-request
                ;; HTML fallback (sy2)
                #:detect-content-kind #:evaluate-endpoint-fallback #:evaluate-all-endpoints
                #:fallback-result #:fb-usable-p #:fb-resolved-url #:fb-hints
                #:remediation-hint #:rh-endpoint #:rh-problem #:rh-suggestion #:rh-alternative-url
                ;; Capability mapper (8oo)
                #:command-request #:make-command-request #:cmd-req-kind
                #:command-response #:cmd-res-ok-p #:cmd-res-kind #:cmd-res-error-detail
                #:capability-gate #:make-capability-gate #:build-capability-gate
                #:operation-allowed-p #:safe-execute
                #:cg-allowed-ops #:cg-denied-ops
                ;; Endpoint classifier (1t2)
                #:endpoint-classification #:make-endpoint-classification
                #:ec-path #:ec-surface #:ec-http-status #:ec-content-type
                #:ec-body-shape #:ec-confidence
                #:classify-endpoint-response #:detect-body-shape)
  (:import-from #:orrery/coalton/core
                #:normalize-status-code #:estimate-cost-cents)
  (:import-from #:orrery/pipeline
                #:projection-state #:projection-state-p #:make-projection-state
                #:reduce-event #:ingest-events
                #:project-usage-summary #:project-activity-feed #:project-alert-state
                #:normalized-snapshot #:normalized-snapshot-p
                #:normalized-snapshot-sessions #:normalized-snapshot-events
                #:normalized-snapshot-alerts #:normalized-snapshot-sync-token
                #:normalize-timestamp
                #:normalize-session-payload #:normalize-event-payload #:normalize-alert-payload
                #:normalize-snapshot-payload)
  (:import-from #:orrery/store
                #:sync-store #:sync-store-p #:make-sync-store
                #:ss-sessions #:ss-cron-jobs #:ss-health #:ss-usage #:ss-events #:ss-alerts #:ss-subagents
                #:ss-last-sync-at #:ss-sync-token
                #:snapshot-from-adapter #:apply-incremental-events #:replay-events #:store->plist))
