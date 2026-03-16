;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; packages.lisp — Package definitions for TUI dashboard shell
;;;
;;; Bead: agent-orrery-eb0.3.1

(defpackage #:orrery/tui
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:cron-record #:health-record
                #:usage-record #:event-record #:alert-record
                #:sr-id #:sr-agent-name #:sr-channel #:sr-status #:sr-model
                #:sr-total-tokens #:sr-estimated-cost-cents
                #:make-cron-record
                #:cr-name #:cr-kind #:cr-interval-s #:cr-status
                #:cr-last-run-at #:cr-next-run-at #:cr-run-count
                #:cr-last-error #:cr-description
                #:hr-component #:hr-status #:hr-latency-ms
                #:er-id #:er-kind #:er-source #:er-timestamp
                #:ar-id #:ar-severity #:ar-title #:ar-fired-at
                #:ur-model #:ur-total-tokens #:ur-estimated-cost-cents)
  (:import-from #:orrery/provider
                #:page #:page-items #:page-offset #:page-limit #:page-total
                #:session-view #:sv-record #:sv-age-seconds #:sv-cost-display #:sv-token-display
                #:cron-view #:cv-record #:cv-overdue-p #:cv-error-p #:cv-interval-display
                #:health-view #:hv-record #:hv-ok-p #:hv-latency-display
                #:event-view #:ev-record #:ev-age-seconds #:ev-severity-indicator
                #:alert-view #:alv-record #:alv-active-p #:alv-age-seconds #:alv-urgency
                #:usage-view #:uv-record #:uv-cost-display #:uv-token-display
                #:dashboard-summary #:dashboard-summary-p
                #:ds-session-count #:ds-active-session-count
                #:ds-cron-count #:ds-overdue-cron-count
                #:ds-health-ok-p #:ds-degraded-components
                #:ds-alert-count #:ds-critical-alert-count
                #:ds-total-tokens #:ds-total-cost-cents #:ds-last-sync-at
                #:query-sessions #:query-cron-jobs #:query-health
                #:query-events #:query-alerts #:query-usage
                #:build-dashboard-summary
                #:format-tokens #:format-cost-cents #:format-age #:format-interval)
  (:import-from #:orrery/store
                #:sync-store #:sync-store-p)
  (:export
   ;; Panel model
   #:panel #:panel-p #:make-panel #:copy-panel
   #:panel-id #:panel-title #:panel-visible-p #:panel-focused-p
   #:panel-row #:panel-col #:panel-height #:panel-width
   ;; Layout
   #:layout #:layout-p #:make-layout #:copy-layout
   #:layout-panels #:layout-active-panel
   #:layout-screen-rows #:layout-screen-cols #:layout-status-line
   #:make-default-layout #:compute-grid #:find-panel #:cycle-focus
   ;; TUI state
   #:tui-state #:tui-state-p #:make-tui-state #:copy-tui-state
   #:ts-layout #:ts-store #:ts-now #:ts-mode
   #:ts-command-input #:ts-message #:ts-running-p
   ;; Keymap
   #:*default-keymap* #:lookup-action
   ;; Actions / dispatch
   #:dispatch-action
   ;; Render operations
   #:render-op #:render-op-p #:make-render-op
   #:rop-row #:rop-col #:rop-text #:rop-attr
   #:render-panel-frame
   #:render-sessions-panel #:render-cron-panel #:render-health-panel
   #:render-events-panel #:render-alerts-panel #:render-usage-panel
   #:render-status-bar #:render-command-palette
   #:render-dashboard
   ;; Session detail (eb0.3.2)
   #:filter-spec #:make-filter-spec #:fs-text-query #:fs-status-filter
   #:fs-model-filter #:fs-sort-key
   #:filter-result #:make-filter-result #:fr-matches #:fr-total-count
   #:fr-match-count #:fr-applied-filters
   #:history-entry #:make-history-entry #:he-timestamp #:he-event-kind #:he-summary
   #:session-detail #:make-session-detail #:sd-view #:sd-history
   #:sd-history-count #:sd-filter
   #:match-filter-p #:apply-filter #:sort-sessions #:tail-history
   #:build-session-detail #:render-session-detail
   #:render-filter-bar
   ;; Analytics cards (eb0.3.4)
   #:time-window #:next-time-window #:time-window-label
   #:analytics-card #:make-analytics-card
   #:ac-title #:ac-value #:ac-unit #:ac-trend #:ac-window
   #:trend-indicator #:render-card-line
   #:analytics-state #:make-analytics-state
   #:as-window #:as-cards #:as-selected-index
   #:build-token-usage-card #:build-cost-card
   #:build-model-distribution-card #:build-session-count-card
   #:build-cost-optimizer-card #:build-capacity-planner-card
   #:build-analytics-state #:cycle-analytics-window
   #:render-analytics-lines
   ;; Cron operations (eb0.3.3)
   #:cron-transition-valid-p #:cron-next-status
   #:cron-op-result #:make-cron-op-result
   #:cor-success-p #:cor-action #:cor-job-name
   #:cor-old-status #:cor-new-status #:cor-message
   #:apply-cron-action #:cron-record-with-new-status
   #:cron-ops-state #:make-cron-ops-state
   #:cos-selected-index #:cos-jobs #:cos-last-result #:cos-confirm-pending
   #:cos-selected-job #:cos-move-selection
   #:cos-request-action #:cos-cancel-action #:cos-confirm-action
   #:cron-status-display #:render-cron-job-line
   #:render-cron-ops-lines #:available-cron-actions
   ;; Shell (impure — croatoan event loop)
   #:*refresh-interval-ms* #:*input-timeout-ms*
   #:paint-render-ops #:clear-screen
   #:handle-resize #:refresh-store-data
   #:read-input #:process-input #:render-frame
   #:run-tui #:start-dashboard))
