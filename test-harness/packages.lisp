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
                #:adapter-error #:adapter-not-supported #:adapter-not-found
                ;; Boundary declaration gate (axv)
                #:boundary-declaration-violation #:boundary-declaration-violation-p
                #:bdv-package-name #:bdv-symbol-name #:bdv-reason
                #:boundary-export-declaration-violations #:boundary-exports-declared-p)
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
                #:classify-endpoint-response #:detect-body-shape
                ;; Handshake probe (bq1)
                #:handshake-result #:handshake-result-p #:make-handshake-result
                #:hs-base-url #:hs-family #:hs-ready-p #:hs-classification #:hs-remediation
                #:handshake-report #:handshake-report-p #:make-handshake-report
                #:hr-results #:hr-overall-ready-p #:hr-summary
                #:classify-response-family #:make-family-remediation #:run-handshake-probe)
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
                #:snapshot-from-adapter #:apply-incremental-events #:replay-events #:store->plist)
  (:import-from #:orrery/adapter
                ;; Decision core (eb0.2.7)
                #:classify-probe-status #:status-to-severity #:assess-probe
                #:aggregate-severities #:compute-verdict #:generate-reasoning
                #:run-decision-pipeline #:verify-replay
                #:probe-finding #:probe-finding-p #:make-probe-finding
                #:pf-domain #:pf-status #:pf-severity #:pf-message #:pf-evidence-ref
                #:severity-thresholds #:severity-thresholds-p #:make-severity-thresholds
                #:st-pass-ceiling #:st-degraded-ceiling
                #:replay-seed #:replay-seed-p #:make-replay-seed
                #:rseed-timestamp #:rseed-version #:rseed-thresholds
                #:decision-record #:decision-record-p #:make-decision-record
                #:dec-verdict #:dec-aggregate-score #:dec-max-severity
                #:dec-finding-count #:dec-findings #:dec-replay-seed #:dec-reasoning
                ;; Schema compat checker (eb0.2.8)
                #:field-sig #:field-sig-p #:make-field-sig
                #:fs-name #:fs-field-type #:fs-required-p #:fs-path
                #:schema-sig #:schema-sig-p #:make-schema-sig
                #:ss-endpoint #:ss-version #:ss-fields #:ss-timestamp
                #:compat-mismatch #:compat-mismatch-p #:make-compat-mismatch
                #:cm-path #:cm-category #:cm-fixture-value #:cm-live-value
                #:cm-severity #:cm-remediation
                #:compat-report #:compat-report-p #:make-compat-report
                #:cr-endpoint #:cr-compatible-p #:cr-mismatches #:cr-max-severity
                #:cr-fixture-sig #:cr-live-sig #:cr-timestamp
                #:compare-field #:compare-schemas #:max-mismatch-severity
                #:check-schema-compatibility #:check-all-schemas
                ;; Replay harness (ufa)
                #:replay-event #:replay-event-p #:make-replay-event
                #:re-sequence-id #:re-event-type #:re-payload #:re-timestamp
                #:replay-stream #:replay-stream-p #:make-replay-stream
                #:rstr-stream-id #:rstr-source #:rstr-events #:rstr-seed #:rstr-metadata
                #:replay-diff #:replay-diff-p #:make-replay-diff
                #:rd-event-id #:rd-diff-kind #:rd-original-value #:rd-replayed-value
                #:replay-report #:replay-report-p #:make-replay-report
                #:rpt-stream-id #:rpt-decisions #:rpt-match-p #:rpt-diff-count #:rpt-diffs
                #:validate-ordering #:event-to-finding
                #:replay-to-decision #:diff-decisions
                #:run-replay #:run-batch-replay
                ;; Gate invariant checker (hrp)
                #:invariant-violation #:invariant-violation-p #:make-invariant-violation
                #:iv-category #:iv-severity #:iv-description #:iv-evidence
                #:invariant-report #:invariant-report-p #:make-invariant-report
                #:ir-pass-p #:ir-violations #:ir-checked-count
                #:ir-pass-count #:ir-fail-count #:ir-timestamp
                #:check-ordering-invariant #:check-determinism-invariant
                #:check-schema-coverage-invariant #:check-decision-consistency-invariant
                #:build-invariant-report #:run-invariant-suite
                ;; Replay artifact schema (n4b)
                #:artifact-kind #:validation-code #:error-severity
                #:validation-error #:validation-error-p #:make-validation-error
                #:ve-field #:ve-code #:ve-message #:ve-severity
                #:artifact-envelope #:artifact-envelope-p #:make-artifact-envelope
                #:ae-artifact-id #:ae-kind #:ae-version #:ae-created-at #:ae-source
                #:ae-checksum #:ae-payload-size #:ae-valid-p #:ae-errors
                #:validate-required-string #:validate-integer-range #:validate-version-format
                #:validate-envelope #:validate-stream-artifact
                #:validate-decision-artifact #:validate-corpus-artifact
                #:summarize-validation #:run-artifact-validation
                ;; Schema regression generators (9oy)
                #:gen-state #:gen-state-p #:make-gen-state
                #:gs-seed #:gs-counter
                #:gen-next-raw #:gen-integer #:gen-element #:gen-string
                #:gen-replay-event #:gen-replay-stream
                #:gen-snapshot-token #:gen-snapshot-sequence
                #:gen-field-sig #:gen-schema-sig #:gen-schema-pair
                #:regression-corpus #:regression-corpus-p #:make-regression-corpus
                #:rc-corpus-id #:rc-seed #:rc-streams #:rc-snapshots
                #:rc-fixture-sigs #:rc-live-sigs #:rc-metadata
                #:gen-regression-corpus
                ;; Capture driver (gzu)
                #:capture-target #:capture-target-p #:make-capture-target
                #:ct-base-url #:ct-token #:ct-profile #:ct-timeout-ms
                #:endpoint-sample #:endpoint-sample-p #:make-endpoint-sample
                #:es-endpoint #:es-status-code #:es-body #:es-latency-ms #:es-timestamp #:es-error-p
                #:capture-snapshot #:capture-snapshot-p #:make-capture-snapshot
                #:cs-snapshot-id #:cs-target #:cs-samples #:cs-timestamp #:cs-duration-ms
                #:capture-result #:capture-result-p #:make-capture-result
                #:cres-snapshots #:cres-artifacts #:cres-diagnostics #:cres-success-p
                #:sample-fixture-endpoint #:sample-endpoint
                #:normalize-sample-to-finding #:assemble-snapshot
                #:snapshot-to-artifact #:snapshot-to-replay-stream
                #:run-capture #:capture-to-decision
                ;; Action-intent algebra (3st)
                #:action-intent #:action-intent-p #:make-action-intent
                #:ai-kind #:ai-target-id #:ai-params
                #:intent-category
                #:intent-result #:intent-result-p #:make-intent-result
                #:ir-status #:ir-payload #:ir-error-message #:ir-intent
                #:intent-list-sessions #:intent-list-cron-jobs #:intent-system-health
                #:intent-list-alerts #:intent-list-subagents #:intent-capabilities
                #:intent-session-history #:intent-trigger-cron #:intent-pause-cron
                #:intent-resume-cron #:intent-acknowledge-alert #:intent-snooze-alert
                #:intent-usage-records #:intent-tail-events
                #:interpret-intent #:interpret-intents #:describe-intent
                ;; Fixture replay compiler (qyn)
                #:fixture-replay-bundle #:fixture-replay-bundle-p #:make-fixture-replay-bundle
                #:frb-bundle-id #:frb-source #:frb-streams #:frb-artifacts
                #:frb-fixture-corpus #:frb-event-count #:frb-snapshot-count #:frb-timestamp
                #:normalize-event->replay-event #:snapshot->replay-events
                #:replay-stream->artifact #:replay-stream->fixture-json
                #:compile-fixture-replay-bundle
                ;; Evidence pack (cto)
                #:parity-entry #:parity-entry-p #:make-parity-entry
                #:pe-endpoint #:pe-fixture-status #:pe-live-status
                #:pe-fixture-body-hash #:pe-live-body-hash #:pe-verdict #:pe-detail
                #:parity-report #:parity-report-p #:make-parity-report
                #:pr-report-id #:pr-entries #:pr-overall-verdict
                #:pr-identical-count #:pr-compatible-count
                #:pr-degraded-count #:pr-incompatible-count #:pr-timestamp
                #:replay-manifest-entry #:replay-manifest-entry-p #:make-replay-manifest-entry
                #:rme-stream-id #:rme-source #:rme-event-count #:rme-seed
                #:rme-artifact-id #:rme-valid-p
                #:replay-manifest #:replay-manifest-p #:make-replay-manifest
                #:rm-manifest-id #:rm-entries #:rm-stream-count
                #:rm-valid-count #:rm-invalid-count #:rm-timestamp
                #:evidence-pack #:evidence-pack-p #:make-evidence-pack
                #:ep-pack-id #:ep-parity-report #:ep-replay-manifest
                #:ep-fixture-decision #:ep-live-decision
                #:ep-fixture-artifact #:ep-live-artifact
                #:ep-gate-ready-p #:ep-blockers #:ep-timestamp #:ep-repro-commands
                #:simple-body-hash #:compare-endpoint-samples
                #:build-parity-report #:build-replay-manifest
                #:generate-repro-commands #:build-evidence-pack
                #:parity-entry-to-json #:parity-report-to-json
                #:replay-manifest-to-json #:evidence-pack-to-json
                ;; Fixture replay compiler (qyn)
                #:fixture-replay-bundle #:fixture-replay-bundle-p #:make-fixture-replay-bundle
                #:frb-bundle-id #:frb-source #:frb-streams #:frb-artifacts
                #:frb-fixture-corpus #:frb-event-count #:frb-snapshot-count #:frb-timestamp
                #:normalize-event->replay-event #:snapshot->replay-events
                #:replay-stream->artifact #:replay-stream->fixture-json
                #:compile-fixture-replay-bundle
                ;; Decision audit log (8x8)
                #:audit-entry #:audit-entry-p #:make-audit-entry
                #:aue-entry-id #:aue-verdict #:aue-aggregate-score #:aue-finding-count
                #:aue-evidence-ref #:aue-gate-id #:aue-context #:aue-timestamp
                #:audit-log #:audit-log-p #:make-audit-log
                #:al-log-id #:al-entries #:al-entry-count
                #:al-pass-count #:al-fail-count #:al-escalate-count
                #:al-first-timestamp #:al-last-timestamp
                #:audit-diff-entry #:audit-diff-entry-p #:make-audit-diff-entry
                #:ade-entry-id #:ade-kind #:ade-old-verdict #:ade-new-verdict #:ade-detail
                #:audit-diff #:audit-diff-p #:make-audit-diff
                #:ad-diff-id #:ad-base-log-id #:ad-target-log-id
                #:ad-entries #:ad-added-count #:ad-removed-count #:ad-changed-count
                #:ad-regressions-p
                #:make-audit-entry-from-decision #:append-to-audit-log
                #:build-audit-log #:diff-audit-logs
                #:audit-entry-to-json #:audit-log-to-json #:audit-diff-to-json
                ;; Health monitor (a40)
                #:health-sample #:health-sample-p #:make-health-sample
                #:hs-endpoint #:hs-status #:hs-latency-ms #:hs-timestamp #:hs-error-detail
                #:health-window #:health-window-p #:make-health-window
                #:hw-start-time #:hw-end-time #:hw-status #:hw-sample-count
                #:health-summary #:health-summary-p #:make-health-summary
                #:hsum-total-probes #:hsum-up-count #:hsum-down-count #:hsum-degraded-count
                #:hsum-uptime-ratio #:hsum-p50-latency-ms #:hsum-p95-latency-ms
                #:hsum-windows #:hsum-first-probe-time #:hsum-last-probe-time
                #:backoff-state #:backoff-state-p #:make-backoff-state
                #:bs-base-ms #:bs-max-ms #:bs-multiplier #:bs-current-ms #:bs-attempt
                #:compute-backoff #:reset-backoff
                #:probe-health #:classify-windows #:build-health-summary
                #:health-summary-to-json
                ;; Event trace canonicalization (v4o)
                #:trace-event #:make-trace-event #:tev-seq-id #:tev-timestamp
                #:tev-source-tag #:tev-event-kind #:tev-payload-hash
                #:trace-stream #:make-trace-stream #:ts-events #:ts-count
                #:trace-diff-result #:tdr-matched-count #:tdr-mismatched-count
                #:tdr-missing-left #:tdr-missing-right #:tdr-details
                #:compute-seq-id #:simple-payload-hash
                #:canonicalize-event #:canonicalize-stream
                #:trace-event< #:dedup-by-seq-id
                #:trace-diff #:trace-parity-p
                #:trace-event->json #:trace-diff->json
                ;; Parity assertion engine (5nl)
                #:tolerance-spec #:make-tolerance-spec
                #:tol-max-mismatches #:tol-max-missing #:tol-required-kinds
                #:assertion-profile #:make-assertion-profile
                #:ap-name #:ap-target #:ap-tolerance #:ap-required-sources
                #:assertion-entry #:make-assertion-entry
                #:ae-kind-label #:ae-expected-count #:ae-actual-count
                #:ae-verdict #:ae-detail
                #:parity-assertion-report
                #:par-report-id #:par-profile-name #:par-target #:par-entries
                #:par-pass-count #:par-fail-count #:par-skip-count #:par-overall-verdict
                #:par-diff-summary #:par-timestamp
                #:*tui-parity-profile* #:*web-parity-profile* #:*mcclim-parity-profile*
                #:make-default-tolerance #:filter-stream-by-sources #:count-by-kind
                #:evaluate-kind-parity #:run-parity-assertion #:parity-report-pass-p
                #:assertion-entry->json #:parity-assertion-report->json
                ;; Gate orchestration runner (c52)
                #:gate-run-config #:make-gate-run-config #:grc-profile
                #:grc-endpoints #:grc-seed
                #:gate-step-result #:make-gate-step-result #:gsr-step-name #:gsr-status
                #:gsr-duration-ms #:gsr-artifact #:gsr-message
                #:gate-run-report #:grr-config #:grr-steps #:grr-verdict
                #:grr-total-duration-ms #:grr-step-count
                #:make-default-config #:run-capture-step #:run-corpus-step
                #:run-parity-step #:run-verdict-step #:execute-gate-run
                #:gate-step->json #:gate-run->json
                ;; Fixture corpus generator (vlm)
                #:corpus-entry #:make-corpus-entry #:ce-endpoint-path #:ce-event-kind
                #:ce-expected-hash #:ce-timestamp #:ce-payload
                #:corpus-manifest #:cman-entries #:cman-version #:cman-seed
                #:cman-checksum #:cman-entry-count
                #:corpus-diff #:cdiff-added #:cdiff-removed #:cdiff-changed
                #:cdiff-unchanged #:cdiff-details
                #:make-corpus-entry-from-sample #:corpus-entry<
                #:compute-corpus-checksum #:build-corpus
                #:diff-corpora #:corpus-stable-p
                #:entry->fixture-json #:corpus->json #:corpus-diff->json
                ;; Usage analytics bridge (68i)
                #:usage-record->coalton-entry #:usage-records->coalton-bucket
                #:coalton-summary->json
                ;; Capture differ (qph)
                #:endpoint-delta #:endpoint-delta-p #:make-endpoint-delta
                #:ed-endpoint #:ed-classification #:ed-status-before #:ed-status-after
                #:ed-body-changed-p #:ed-latency-delta-ms #:ed-detail
                #:capture-diff #:capture-diff-p #:make-capture-diff
                #:cd-diff-id #:cd-deltas #:cd-endpoint-count
                #:cd-identical-count #:cd-compatible-count #:cd-regressed-count
                #:cd-improved-count #:cd-new-count #:cd-removed-count #:cd-regressions-p
                #:diff-endpoint-samples #:diff-capture-results #:capture-diff-to-json
                ;; Playwright canonicalizer-lock bridge (8e2)
                #:canonicalizer-lock-input #:canonicalizer-lock-input-p #:make-canonicalizer-lock-input
                #:cli-scenario-id #:cli-command #:cli-command-fp #:cli-screenshot-path
                #:cli-trace-path #:cli-screenshot-ok-p #:cli-trace-ok-p #:cli-canonical-ok-p
                #:lock-bridge-verdict #:lock-bridge-verdict-p #:make-lock-bridge-verdict
                #:lbv-pass-p #:lbv-command #:lbv-command-fp #:lbv-artifact-root
                #:lbv-complete-count #:lbv-missing-scenarios #:lbv-detail #:lbv-timestamp
                #:lock-bridge-verdict->json))
