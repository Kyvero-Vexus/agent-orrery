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
   #:cap-name #:cap-description #:cap-supported-p
   ;; Audit trail entry (CL-side)
   #:audit-trail-entry #:audit-trail-entry-p #:copy-audit-trail-entry
   #:make-audit-trail-entry
   #:ate-seq #:ate-timestamp #:ate-category #:ate-severity
   #:ate-actor #:ate-summary #:ate-detail #:ate-hash
   ;; Analytics summary (CL-side)
   #:analytics-summary #:analytics-summary-p #:copy-analytics-summary
   #:make-analytics-summary
   #:asm-total-sessions #:asm-avg-duration-s #:asm-median-tokens
   #:asm-avg-tokens-per-msg #:asm-total-cost-cents
   ;; Duration bucket record
   #:duration-bucket-record #:duration-bucket-record-p
   #:make-duration-bucket-record
   #:dbr-label #:dbr-count
   ;; Efficiency record
   #:efficiency-record #:efficiency-record-p
   #:make-efficiency-record
   #:efr-session-id #:efr-tokens-per-message
   #:efr-tokens-per-minute #:efr-cost-per-1k))

(defpackage #:orrery/adapter
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:cron-record #:health-record
                #:usage-record #:event-record #:alert-record
                #:subagent-record #:history-entry #:adapter-capability
                ;; Accessors needed by performance-soak (eb0.7.1)
                #:sr-id #:er-kind
                #:ur-model #:ur-prompt-tokens #:ur-completion-tokens
                #:ur-total-tokens #:ur-estimated-cost-cents #:ur-timestamp
                #:ar-id #:ar-severity #:ar-title #:ar-source #:ar-fired-at)
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
   #:adapter-not-found-id
   ;; Generic starter kit (eb0.6.2)
   #:starter-endpoint-spec #:starter-endpoint-spec-p #:copy-starter-endpoint-spec
   #:make-starter-endpoint-spec
   #:ses-key #:ses-method #:ses-path #:ses-decode-fn #:ses-result-mode
   #:ses-capability-name #:ses-description #:ses-supported-p
   #:generic-runtime-adapter #:make-generic-runtime-adapter #:make-reference-starter-adapter
   #:starter-adapter-name #:starter-base-url #:starter-request-fn #:starter-endpoint-table
   #:make-default-starter-endpoint-specs
   #:find-starter-endpoint #:register-starter-endpoint #:invoke-starter-endpoint
   ;; Preflight (cne)
   #:preflight-check #:preflight-check-p #:make-preflight-check
   #:pc-name #:pc-status #:pc-message #:pc-details
   #:preflight-report #:preflight-report-p #:make-preflight-report
   #:pr-checks #:pr-overall-status #:pr-timestamp #:pr-adapter-name
   #:run-preflight #:compute-overall-status #:preflight-report-to-sexp
   ;; Gate runner (id9)
   #:failure-policy #:failure-policy-p #:make-failure-policy
   #:fp-check-name #:fp-action #:fp-rationale
   #:gate-result #:gate-result-p #:make-gate-result
   #:gr-gate-passed-p #:gr-applied-policies #:gr-report #:gr-exit-code
   #:*default-failure-policies*
   #:apply-failure-policies #:run-gate
   ;; Preflight JSON (apd)
   #:preflight-report-to-json #:gate-result-to-json
   ;; Contract harness (8ro)
   #:runtime-target #:runtime-target-p #:make-runtime-target
   #:rt-profile #:rt-base-url #:rt-token #:rt-description
   #:contract-check #:contract-check-p #:make-contract-check
   #:cc-endpoint-name #:cc-verdict #:cc-expected #:cc-actual #:cc-message
   #:harness-result #:harness-result-p #:make-harness-result
   #:chr-target #:chr-checks #:chr-pass-count #:chr-fail-count
   #:chr-skip-count #:chr-overall-verdict #:chr-artifacts
   #:*standard-contracts*
   #:validate-runtime-target #:run-contract-harness
   #:harness-result-to-json #:write-harness-artifact
   ;; Probe orchestrator (cbw)
   #:classified-failure #:classified-failure-p #:make-classified-failure
   #:cf-failure-class #:cf-check #:cf-remediation
   #:s1-gate-result #:s1-gate-result-p #:make-s1-gate-result
   #:s1-verdict #:s1-profile #:s1-harness-result
   #:s1-classified-failures #:s1-diagnostics
   #:classify-check-failure #:run-s1-probe #:s1-gate-result-to-json
   ;; Compatibility report (xg8)
   #:capability-gap #:capability-gap-p #:make-capability-gap
   #:cg-capability-name #:cg-required-by #:cg-status #:cg-remediation
   #:parity-gate-signal #:parity-gate-signal-p #:make-parity-gate-signal
   #:pgs-epic-name #:pgs-readiness #:pgs-gaps #:pgs-summary
   #:compatibility-report #:compatibility-report-p #:make-compatibility-report
   #:cr-source-verdict #:cr-signals #:cr-overall-readiness
   #:cr-total-gaps #:cr-timestamp
   #:*epic-requirements*
   #:generate-compatibility-report #:compatibility-report-to-json
   ;; Conformance matrix (dbc)
   #:coverage-entry #:coverage-entry-p #:make-coverage-entry
   #:ce-endpoint-name #:ce-coverage #:ce-tested-at #:ce-test-verdict #:ce-notes
   #:conformance-matrix #:conformance-matrix-p #:make-conformance-matrix
   #:cm-adapter-name #:cm-adapter-version #:cm-entries
   #:cm-degradation-mode #:cm-minimum-coverage #:cm-built-at
   #:conformance-check-result #:conformance-check-result-p
   #:make-conformance-check-result
   #:ccr-conformant-p #:ccr-violations #:ccr-degradation-action #:ccr-summary
   #:build-conformance-matrix #:check-conformance #:conformance-matrix-to-json
   ;; Transcript capture (5lt)
   #:transcript-entry #:transcript-entry-p #:make-transcript-entry
   #:te-direction #:te-method #:te-path #:te-status-code
   #:te-content-type #:te-body #:te-timestamp
   #:transcript #:transcript-p #:make-transcript
   #:tx-name #:tx-target-url #:tx-entries #:tx-captured-at #:tx-notes
   #:replay-result #:replay-result-p #:make-replay-result
   #:rr-transcript #:rr-matches #:rr-mismatches #:rr-replay-verdict
   #:capture-response #:build-transcript
   #:transcript-to-json #:load-transcript-from-json #:replay-transcript
   ;; Schema drift detector (gk1)
   #:schema-field #:schema-field-p #:make-schema-field
   #:sf-name #:sf-expected-type #:sf-required-p
   #:protocol-schema #:protocol-schema-p #:make-protocol-schema
   #:ps-endpoint-name #:ps-version #:ps-fields
   #:drift-finding #:drift-finding-p #:make-drift-finding
   #:df-field-name #:df-drift-type #:df-severity #:df-message #:df-remediation
   #:drift-report #:drift-report-p #:make-drift-report
   #:dr-endpoint-name #:dr-schema-version #:dr-findings
   #:dr-compatible-p #:dr-max-severity #:dr-timestamp
   #:*health-schema* #:*sessions-list-schema* #:*standard-schemas*
   #:parse-payload-fields #:detect-drift #:detect-all-drift
   #:drift-report-to-json
   ;; Evidence bundle (7rj)
   #:blocker-entry #:blocker-entry-p #:make-blocker-entry
   #:be-blocker-class #:be-reason-code #:be-description
   #:be-resolution #:be-remediation-hint
   #:evidence-bundle #:evidence-bundle-p #:make-evidence-bundle
   #:eb-gate-id #:eb-target-profile #:eb-decision
   #:eb-s1-verdict #:eb-conformance-summary #:eb-drift-compatible-p
   #:eb-blockers #:eb-artifact-shas #:eb-timestamp #:eb-notes
   #:classify-blockers #:build-evidence-bundle #:evidence-bundle-to-json
   ;; Gate decision engine (g8s)
   #:next-action #:next-action-p #:make-next-action
   #:na-action-id #:na-urgency #:na-description #:na-owner
   #:gate-decision-record #:gate-decision-record-p #:make-gate-decision-record
   #:gdr-gate-id #:gdr-outcome #:gdr-reason #:gdr-next-actions
   #:gdr-evidence-gate-id #:gdr-blocker-count #:gdr-can-close-gate-p #:gdr-timestamp
   #:decide-s1-gate #:gate-decision-to-json
   ;; Gate orchestrator (o0p)
   #:remediation-step #:remediation-step-p #:make-remediation-step
   #:rs-step-id #:rs-action-type #:rs-target #:rs-description #:rs-depends-on
   #:resolution-plan #:resolution-plan-p #:make-resolution-plan
   #:rp-decision-gate-id #:rp-primary-action #:rp-remediation-steps
   #:rp-blocker-report #:rp-unblock-targets #:rp-timestamp
   #:orchestrate-resolution #:resolution-plan-to-json
   ;; Interface matrix (4od)
   #:interface-capability #:interface-capability-p #:make-interface-capability
   #:ic-name #:ic-interface #:ic-required-p #:ic-adapter-endpoint #:ic-fixture-available-p
   #:work-packet #:work-packet-p #:make-work-packet
   #:wp-interface-kind #:wp-epic-id #:wp-readiness
   #:wp-capabilities #:wp-missing-capabilities #:wp-fixture-gaps #:wp-kickoff-checklist
   #:interface-matrix #:interface-matrix-p #:make-interface-matrix
   #:im-packets #:im-shared-fixtures #:im-adapter-coverage-pct #:im-timestamp
   #:*tui-requirements* #:*web-requirements* #:*mcclim-requirements*
   #:generate-interface-matrix #:interface-matrix-to-json
   ;; Capability contract (aei)
   #:capability-schema #:capability-schema-p #:make-capability-schema
   #:cs-adapter-name #:cs-adapter-version #:cs-protocol-version
   #:cs-endpoints #:cs-semantic-map #:cs-metadata
   #:endpoint-capability #:endpoint-capability-p #:make-endpoint-capability
   #:ec-cap-path #:ec-cap-operation #:ec-cap-semantic
   #:ec-cap-supported-p #:ec-cap-requires-auth
   #:validation-issue #:validation-issue-p #:make-validation-issue
   #:vi-severity #:vi-field #:vi-message
   #:validation-result #:validation-result-p #:make-validation-result
   #:vr-valid-p #:vr-issues
   #:validate-schema #:validate-endpoint-capability
   #:negotiation-result #:negotiation-result-p #:make-negotiation-result
   #:nr-outcome #:nr-available-operations #:nr-denied-operations
   #:nr-requires-elevation #:nr-diagnostics
   #:negotiate-capabilities
   ;; Decision core (eb0.2.7)
   #:monitor-status #:probe-domain #:gate-verdict
   #:probe-finding #:probe-finding-p #:make-probe-finding
   #:pf-domain #:pf-status #:pf-severity #:pf-message #:pf-evidence-ref
   #:severity-thresholds #:severity-thresholds-p #:make-severity-thresholds
   #:st-pass-ceiling #:st-degraded-ceiling
   #:replay-seed #:replay-seed-p #:make-replay-seed
   #:rseed-timestamp #:rseed-version #:rseed-thresholds
   #:decision-record #:decision-record-p #:make-decision-record
   #:dec-verdict #:dec-aggregate-score #:dec-max-severity
   #:dec-finding-count #:dec-findings #:dec-replay-seed #:dec-reasoning
   #:classify-probe-status #:status-to-severity #:assess-probe
   #:aggregate-severities #:compute-verdict #:generate-reasoning
   #:run-decision-pipeline #:verify-replay
   ;; Schema compat checker (eb0.2.8)
   #:field-kind #:field-sig #:field-sig-p #:make-field-sig
   #:fs-name #:fs-field-type #:fs-required-p #:fs-path
   #:schema-sig #:schema-sig-p #:make-schema-sig
   #:ss-endpoint #:ss-version #:ss-fields #:ss-timestamp
   #:compat-severity #:compat-category
   #:compat-mismatch #:compat-mismatch-p #:make-compat-mismatch
   #:cm-path #:cm-category #:cm-fixture-value #:cm-live-value
   #:cm-severity #:cm-remediation
   #:compat-report #:compat-report-p #:make-compat-report
   #:cr-endpoint #:cr-compatible-p #:cr-mismatches #:cr-max-severity
   #:cr-fixture-sig #:cr-live-sig #:cr-timestamp
   #:compare-field #:compare-schemas #:max-mismatch-severity
   #:check-schema-compatibility #:check-all-schemas
   ;; Replay harness (ufa)
   #:replay-event-type #:replay-source
   #:replay-event #:replay-event-p #:make-replay-event
   #:re-sequence-id #:re-event-type #:re-payload #:re-timestamp
   #:replay-stream #:replay-stream-p #:make-replay-stream
   #:rstr-stream-id #:rstr-source #:rstr-events #:rstr-seed #:rstr-metadata
   #:diff-kind
   #:replay-diff #:replay-diff-p #:make-replay-diff
   #:rd-event-id #:rd-diff-kind #:rd-original-value #:rd-replayed-value #:rd-description
   #:replay-report #:replay-report-p #:make-replay-report
   #:rpt-stream-id #:rpt-decisions #:rpt-match-p #:rpt-diff-count #:rpt-diffs #:rpt-elapsed-ms
   #:validate-ordering #:event-to-finding
   #:replay-to-decision #:diff-decisions
   #:run-replay #:run-batch-replay
   ;; Gate invariant checker (hrp)
   #:invariant-category #:violation-severity
   #:invariant-violation #:invariant-violation-p #:make-invariant-violation
   #:iv-category #:iv-severity #:iv-description #:iv-evidence
   #:invariant-report #:invariant-report-p #:make-invariant-report
   #:ir-pass-p #:ir-violations #:ir-checked-count #:ir-pass-count
   #:ir-fail-count #:ir-timestamp
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
   ;; Capture driver (gzu)
   #:capture-profile #:capture-target #:capture-target-p #:make-capture-target
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
   #:intent-kind #:intent-category
   #:action-intent #:action-intent-p #:make-action-intent
   #:ai-kind #:ai-target-id #:ai-params
   #:result-status
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
   ;; Replay protocol bridge (a47)
   #:replay-surface
   #:protocol-parity-row #:protocol-parity-row-p #:make-protocol-parity-row
   #:ppr-sequence-id #:ppr-web-kind #:ppr-tui-kind #:ppr-mcclim-kind
   #:ppr-web-hash #:ppr-tui-hash #:ppr-mcclim-hash #:ppr-parity-p #:ppr-detail
   #:protocol-parity-fixture #:protocol-parity-fixture-p #:make-protocol-parity-fixture
   #:ppf-fixture-id #:ppf-rows #:ppf-parity-pass-p #:ppf-stream-count #:ppf-row-count #:ppf-timestamp
   #:event-kind->ui-kind #:trace-event->ui-message #:trace-stream->ui-messages
   #:build-protocol-parity-fixture #:protocol-parity-fixture->json
   ;; Evidence pack (cto)
   #:parity-verdict
   #:parity-entry #:parity-entry-p #:make-parity-entry
   #:pe-endpoint #:pe-fixture-status #:pe-live-status
   #:pe-fixture-body-hash #:pe-live-body-hash #:pe-verdict #:pe-detail
   #:parity-report #:parity-report-p #:make-parity-report
   #:pr-report-id #:pr-fixture-snapshot-id #:pr-live-snapshot-id
   #:pr-entries #:pr-overall-verdict #:pr-endpoint-count
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
   #:diff-kind
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
   #:monitor-status
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
   #:event-kind #:source-tag
   #:trace-event #:make-trace-event #:tev-seq-id #:tev-timestamp
   #:tev-source-tag #:tev-event-kind #:tev-payload-hash
   #:trace-stream #:make-trace-stream #:ts-events #:ts-count
   #:trace-diff-result #:make-trace-diff-result
   #:tdr-matched-count #:tdr-mismatched-count #:tdr-missing-left
   #:tdr-missing-right #:tdr-details
   #:compute-seq-id #:simple-payload-hash
   #:canonicalize-event #:canonicalize-stream
   #:trace-event< #:dedup-by-seq-id
   #:trace-diff #:trace-parity-p
   #:trace-event->json #:trace-diff->json
   ;; Parity assertion engine (5nl)
   #:ui-target
   #:tolerance-spec #:tolerance-spec-p #:make-tolerance-spec
   #:tol-max-mismatches #:tol-max-missing #:tol-required-kinds
   #:assertion-profile #:assertion-profile-p #:make-assertion-profile
   #:ap-name #:ap-target #:ap-tolerance #:ap-required-sources
   #:assertion-verdict
   #:assertion-entry #:assertion-entry-p #:make-assertion-entry
   #:ae-kind-label #:ae-source-label #:ae-expected-count #:ae-actual-count
   #:ae-verdict #:ae-detail
   #:parity-assertion-report #:parity-assertion-report-p #:make-parity-assertion-report
   #:par-report-id #:par-profile-name #:par-target #:par-entries
   #:par-pass-count #:par-fail-count #:par-skip-count #:par-overall-verdict
   #:par-diff-summary #:par-timestamp
   #:*tui-parity-profile* #:*web-parity-profile* #:*mcclim-parity-profile*
   #:make-default-tolerance #:filter-stream-by-sources #:count-by-kind
   #:evaluate-kind-parity #:compute-report-id
   #:run-parity-assertion #:parity-report-pass-p
   #:assertion-entry->json #:parity-assertion-report->json
   ;; Observability trace contract (eb0.6.6)
   #:trace-obligation #:trace-obligation-p #:make-trace-obligation
   #:tobl-event-kind #:tobl-source-tag #:tobl-min-count #:tobl-description
   #:trace-contract #:trace-contract-p #:make-trace-contract
   #:tc-name #:tc-target #:tc-obligations #:tc-version
   #:obligation-verdict
   #:obligation-result #:obligation-result-p #:make-obligation-result
   #:obr-obligation #:obr-actual-count #:obr-verdict #:obr-detail
   #:contract-verification #:contract-verification-p #:make-contract-verification
   #:cv-contract-name #:cv-target #:cv-results
   #:cv-satisfied-count #:cv-violated-count #:cv-exceeded-count
   #:cv-overall-pass-p #:cv-timestamp
   #:trace-collector #:trace-collector-p #:make-trace-collector
   #:tcol-streams #:tcol-count
   #:make-empty-collector #:collector-register-stream #:collector-get-stream
   #:make-core-obligations
   #:make-tui-contract #:make-web-contract #:make-mcclim-contract
   #:*standard-trace-contracts*
   #:check-obligation #:verify-trace-contract
   #:verify-all-contracts #:cross-ui-parity-matrix
   #:obligation-result->json #:contract-verification->json
   ;; Cross-UI evidence verifier (ai0)
   #:evidence-runner-kind #:scenario-status
   #:evidence-artifact-kind #:evidence-finding-severity #:cross-ui-parity-verdict
   #:scenario-evidence #:scenario-evidence-p #:make-scenario-evidence
   #:sce-scenario-id #:sce-status #:sce-detail
   #:evidence-artifact #:evidence-artifact-p #:make-evidence-artifact
   #:ea-scenario-id #:ea-artifact-kind #:ea-path #:ea-present-p #:ea-detail
   #:runner-evidence-manifest #:runner-evidence-manifest-p #:make-runner-evidence-manifest
   #:rem-runner-id #:rem-runner-kind #:rem-command #:rem-scenarios #:rem-artifacts #:rem-timestamp
   #:evidence-finding #:evidence-finding-p #:make-evidence-finding
   #:ef-severity #:ef-code #:ef-message
   #:scenario-coverage-row #:scenario-coverage-row-p #:make-scenario-coverage-row
   #:scr-scenario-id #:scr-passed-p #:scr-status #:scr-artifact-ok-p #:scr-missing-artifacts
   #:evidence-compliance-report #:evidence-compliance-report-p #:make-evidence-compliance-report
   #:ecr-runner-id #:ecr-runner-kind #:ecr-pass-p #:ecr-findings #:ecr-coverage
   #:ecr-required-scenarios-covered #:ecr-required-scenarios-total #:ecr-timestamp
   #:parity-row #:parity-row-p #:make-parity-row
   #:pry-web-scenario #:pry-tui-scenario #:pry-web-pass-p #:pry-tui-pass-p #:pry-verdict #:pry-detail
   #:evidence-parity-report #:evidence-parity-report-p #:make-evidence-parity-report
   #:epr-pass-p #:epr-rows #:epr-match-count #:epr-mismatch-count #:epr-missing-count
   #:cross-ui-evidence-report #:cross-ui-evidence-report-p #:make-cross-ui-evidence-report
   #:cuer-pass-p #:cuer-web-report #:cuer-tui-report #:cuer-parity-report #:cuer-timestamp
   #:*default-web-scenarios* #:*default-tui-scenarios* #:*default-scenario-mapping*
   #:*web-required-artifacts* #:*tui-required-artifacts*
   #:*expected-web-command* #:*expected-tui-command*
   #:normalize-scenario-id #:find-scenario #:artifact-present-p
   #:verify-runner-evidence #:build-evidence-parity-report #:verify-cross-ui-evidence
   #:evidence-compliance-report->json #:evidence-parity-report->json
   #:cross-ui-evidence-report->json
   ;; Playwright evidence compiler (yzx)
   #:*playwright-required-scenarios* #:*playwright-deterministic-command*
   #:infer-web-runner-kind #:infer-playwright-scenario-id #:infer-web-artifact-kind
   #:compile-playwright-evidence-manifest
   ;; Cross-UI parity suite + conformance report (eb0.6.3)
   #:conformance-target
   #:target-conformance-row #:target-conformance-row-p #:make-target-conformance-row
   #:tcr-target #:tcr-contract-pass-p #:tcr-contract-violations #:tcr-parity-pass-p
   #:tcr-v2-module-pass-p #:tcr-v2-missing-count
   #:tcr-evidence-required-p #:tcr-evidence-pass-p #:tcr-overall-pass-p #:tcr-detail
   #:cross-ui-conformance-report #:cross-ui-conformance-report-p #:make-cross-ui-conformance-report
   #:cuc-pass-p #:cuc-target-rows #:cuc-contract-results #:cuc-pairwise-parity-results
   #:cuc-evidence-report #:cuc-required-target-count #:cuc-passing-target-count
   #:cuc-timestamp #:cuc-deterministic-commands
   #:find-contract-verification #:parity-reports-for-target #:target-evidence-pass-p
   #:cross-ui-deterministic-commands
   #:run-cross-ui-parity-suite
   #:target-conformance-row->json #:cross-ui-conformance-report->json
   ;; Performance/soak suite (eb0.7.1)
   #:soak-profile
   #:soak-config #:soak-config-p #:make-soak-config
   #:sc-profile #:sc-session-count #:sc-event-count #:sc-usage-hours
   #:sc-alert-count #:sc-iterations #:sc-seed
   #:soak-timing #:soak-timing-p #:make-soak-timing
   #:st-operation #:st-iterations #:st-total-ms #:st-min-ms #:st-max-ms
   #:st-mean-ms #:st-items-processed #:st-throughput-per-sec
   #:soak-report #:soak-report-p #:make-soak-report
   #:srep-profile #:srep-pass-p #:srep-timings #:srep-total-items
   #:srep-total-ms #:srep-peak-memory-kb #:srep-timestamp #:srep-seed
   #:make-soak-profile-config #:measure-operation #:run-soak-suite
   #:soak-timing->json #:soak-report->json
   ;; Resilience suite (eb0.7.2)
   #:fault-class #:recovery-action
   #:fault-scenario #:fault-scenario-p #:make-fault-scenario
   #:fs-scenario-id #:fs-fault-class #:fs-target-operation #:fs-description
   #:fs-inject-fn #:fs-expected-recovery #:fs-expected-condition-type
   #:resilience-result #:resilience-result-p #:make-resilience-result
   #:rr-scenario-id #:rr-pass-p #:rr-fault-class #:rr-actual-recovery
   #:rr-expected-recovery #:rr-condition-caught-p #:rr-condition-type-match-p
   #:rr-elapsed-ms #:rr-detail
   #:resilience-report #:resilience-report-p #:make-resilience-report
   #:rrep-pass-p #:rrep-total #:rrep-passed #:rrep-failed #:rrep-results #:rrep-timestamp
   #:fault-injecting-adapter #:make-fault-injecting-adapter
   #:fia-delegate #:fia-fault-fn #:fia-target-op
   #:attempt-with-recovery
   #:make-default-resilience-scenarios #:run-resilience-scenario #:run-resilience-suite
   #:resilience-result->json #:resilience-report->json
   ;; Evidence manifest validator (qo5, oo1)
   #:manifest-artifact #:manifest-artifact-p #:make-manifest-artifact
   #:manifest-artifact-scenario-id #:manifest-artifact-kind
   #:manifest-artifact-path #:manifest-artifact-exists-p
   #:manifest-artifact-size-bytes
   #:e2e-manifest #:e2e-manifest-p #:make-e2e-manifest
   #:e2e-manifest-suite #:e2e-manifest-artifacts
   #:e2e-manifest-scenarios-required #:e2e-manifest-deterministic-command
   #:e2e-manifest-valid-p #:e2e-manifest-missing #:e2e-manifest-errors
   #:normalize-artifact-path #:normalize-manifest-artifacts #:normalize-e2e-manifest
   #:validate-e2e-manifest #:validate-and-normalize-e2e-manifest
   #:epic3-t1-t6-evidence-ok-p
   #:report-manifest-validity #:ci-check-all-evidence #:discover-artifacts-in-dir
   ;; TUI scenario contracts (igw.1)
   #:tui-scenario-id
   #:tui-scenario-contract #:tui-scenario-contract-p #:make-tui-scenario-contract
   #:tsc-id #:tsc-name #:tsc-deterministic-command #:tsc-fixture-assumptions
   #:tsc-required-artifacts #:tsc-artifact-dir
   #:tui-scenario-contracts #:tui-deterministic-contract-command
   #:tui-contracts-cover-t1-t6-p #:missing-tui-contract-artifacts
   ;; UI protocol boundary (sdk)
   #:ui-surface #:ui-message-kind #:ui-error-kind
   #:ui-message #:ui-message-p #:make-ui-message
   #:uim-id #:uim-surface #:uim-kind #:uim-payload #:uim-timestamp #:uim-sequence #:uim-deterministic-key
   #:ui-contract #:ui-contract-p #:make-ui-contract
   #:uic-surface #:uic-kind #:uic-required-fields #:uic-schema-version
   #:ui-error-adt #:ui-error-adt-p #:make-ui-error-adt
   #:uie-kind #:uie-code #:uie-message #:uie-recoverable-p #:uie-details
   #:ui-replay-hook #:ui-replay-hook-p #:make-ui-replay-hook
   #:urh-hook-id #:urh-surface #:urh-deterministic-command #:urh-artifact-dir #:urh-seed #:urh-enabled-p
   #:make-ui-message-id #:make-ui-message* #:validate-ui-message #:project-ui-error
   #:ui-message->json #:ui-contract->json #:ui-error->json #:ui-replay-hook->json
   ;; UI protocol schema (4ua)
   #:ui-protocol-surface #:ui-protocol-kind
   #:ui-schema-field #:ui-schema-field-p #:make-ui-schema-field
   #:usf-name #:usf-required-p #:usf-type-tag #:usf-default-value
   #:ui-protocol-schema #:ui-protocol-schema-p #:make-ui-protocol-schema
   #:ups-surface #:ups-kind #:ups-version #:ups-fields #:ups-compat-versions
   #:ui-schema-migration #:ui-schema-migration-p #:make-ui-schema-migration
   #:usm-surface #:usm-kind #:usm-from-version #:usm-to-version #:usm-transformer
   #:make-default-ui-protocol-schema #:validate-payload-against-ui-schema
   #:migrate-ui-payload #:ui-protocol-schema->json #:ui-schema-migration->json
   ;; Boundary declaration gate (axv)
   #:boundary-declaration-kind
   #:boundary-declaration-violation #:boundary-declaration-violation-p
   #:make-boundary-declaration-violation
   #:bdv-package-name #:bdv-symbol-name #:bdv-reason
   #:*boundary-declaration-packages*
   #:function-where-from-name #:symbol-has-declared-ftype-p
   #:symbol-has-public-type-definition-p #:package-defstruct-helper-symbols
   #:boundary-symbol-declaration-kind #:boundary-export-declaration-violations
   #:boundary-exports-declared-p
   ;; Design-doc sync gate (mmw)
   #:*design-doc-requirement-sentence*
   #:design-doc-sync-result #:design-doc-sync-result-p #:make-design-doc-sync-result
   #:ddsr-bead-id #:ddsr-requirement-present-p #:ddsr-docs-found-p
   #:ddsr-matching-doc-paths #:ddsr-detail
   #:bead-acceptance-result #:bead-acceptance-result-p #:make-bead-acceptance-result
   #:bar-bead-id #:bar-design-doc-sync-ok-p #:bar-epic3-evidence-ok-p
   #:bar-epic4-evidence-ok-p #:bar-overall-ok-p #:bar-detail
   #:bead-requires-design-docs-p #:find-design-docs-for-bead
   #:evaluate-design-doc-sync #:epic4-s1-s6-evidence-ok-p #:evaluate-bead-acceptance
   #:design-doc-sync-result->json #:bead-acceptance-result->json
   ;; Scenario planning bridge (20d)
   #:scenario-projection #:scenario-projection-p #:make-scenario-projection
   #:sproj-scenario-name #:sproj-total-tokens #:sproj-total-cost
   #:sproj-sessions #:sproj-cron-invocations #:sproj-budget-util-pct #:sproj-signals
   #:coalton-projection->cl #:scenario-projection->json
   ;; v2 projection bridge (4zp)
   #:audit-entry-projection #:audit-entry-projection-p #:make-audit-entry-projection
   #:aep-seq #:aep-timestamp #:aep-category #:aep-severity #:aep-actor
   #:aep-summary #:aep-detail #:aep-hash
   #:session-analytics-projection #:session-analytics-projection-p #:make-session-analytics-projection
   #:sap-total-sessions #:sap-avg-duration-seconds #:sap-avg-tokens-per-msg
   #:sap-median-tokens #:sap-total-cost-cents #:sap-duration-buckets #:sap-efficiency-summaries
   #:duration-bucket-projection #:duration-bucket-projection-p #:make-duration-bucket-projection
   #:dbp-label #:dbp-count
   #:efficiency-projection #:efficiency-projection-p #:make-efficiency-projection
   #:efp-session-id #:efp-tokens-per-message #:efp-tokens-per-minute #:efp-cost-per-1k
   #:coalton-audit-entry->projection #:audit-entry-projection->json
   #:coalton-analytics->projection #:session-analytics-projection->json
   #:page-request #:page-request-p #:make-page-request
   #:pr-offset #:pr-limit #:pr-sort-key #:pr-sort-order
   #:page-response #:page-response-p #:make-page-response
   #:pres-items #:pres-total #:pres-offset #:pres-limit #:pres-has-more-p
   #:paginate-items
   ;; Gate orchestration runner (c52)
   #:run-profile #:step-status
   #:gate-run-config #:make-gate-run-config #:grc-profile #:grc-endpoints
   #:grc-seed #:grc-verbose-p
   #:gate-step-result #:make-gate-step-result #:gsr-step-name #:gsr-status
   #:gsr-duration-ms #:gsr-artifact #:gsr-message
   #:gate-run-report #:make-gate-run-report #:grr-config #:grr-steps
   #:grr-verdict #:grr-total-duration-ms #:grr-step-count
   #:make-default-config #:run-capture-step #:run-corpus-step
   #:run-parity-step #:run-verdict-step #:execute-gate-run
   #:gate-step->json #:gate-run->json
   ;; Fixture corpus generator (vlm)
   #:corpus-entry #:make-corpus-entry #:ce-endpoint-path #:ce-event-kind
   #:ce-expected-hash #:ce-timestamp #:ce-payload
   #:corpus-manifest #:make-corpus-manifest #:cman-entries #:cman-version
   #:cman-seed #:cman-checksum #:cman-entry-count
   #:corpus-diff #:make-corpus-diff #:cdiff-added #:cdiff-removed
   #:cdiff-changed #:cdiff-unchanged #:cdiff-details
   #:make-corpus-entry-from-sample #:corpus-entry<
   #:compute-corpus-checksum #:build-corpus
   #:diff-corpora #:corpus-stable-p
   #:entry->fixture-json #:corpus->json #:corpus-diff->json
   ;; Usage analytics bridge (68i)
   #:usage-record->coalton-entry #:usage-records->coalton-bucket
   #:coalton-summary->json
   ;; Adapter anomaly detector (mhg)
   #:adapter-anomaly-snapshot #:adapter-anomaly-snapshot-p #:make-adapter-anomaly-snapshot
   #:adapter-anomaly-snapshot-adapter-id #:adapter-anomaly-snapshot-session-count
   #:adapter-anomaly-snapshot-usage-records
   #:adapter-anomaly-result #:adapter-anomaly-result-p #:make-adapter-anomaly-result
   #:adapter-anomaly-result-primary-adapter #:adapter-anomaly-result-secondary-adapter
   #:adapter-anomaly-result-report #:adapter-anomaly-result-divergence-findings
   #:adapter-anomaly-result-anomaly-count #:adapter-anomaly-result-risk-score
   #:adapter-anomaly-result-severity-label
   #:detect-adapter-anomalies #:snapshot->json #:anomaly-result->json
   ;; Capture differ (qph)
   #:diff-classification
   #:endpoint-delta #:endpoint-delta-p #:make-endpoint-delta
   #:ed-endpoint #:ed-classification #:ed-status-before #:ed-status-after
   #:ed-body-changed-p #:ed-latency-delta-ms #:ed-detail
   #:capture-diff #:capture-diff-p #:make-capture-diff
   #:cd-diff-id #:cd-deltas #:cd-endpoint-count
   #:cd-identical-count #:cd-compatible-count #:cd-regressed-count
   #:cd-improved-count #:cd-new-count #:cd-removed-count #:cd-regressions-p
   #:diff-endpoint-samples #:diff-capture-results #:capture-diff-to-json
   ;; Snapshot drift diagnostic (3nk)
   #:diagnostic-disposition
   #:snapshot-drift-diagnostic #:snapshot-drift-diagnostic-p
   #:make-snapshot-drift-diagnostic
   #:sdd-snapshot-id #:sdd-profile #:sdd-endpoint-count
   #:sdd-drift-reports #:sdd-breaking-count #:sdd-degrading-count
   #:sdd-cosmetic-count #:sdd-info-count
   #:sdd-disposition #:sdd-gate-evidence-ref #:sdd-timestamp
   #:*snapshot-endpoint-schemas*
   #:analyze-snapshot-drift
   #:drift-comparison #:drift-comparison-p #:make-drift-comparison
   #:dc-fixture-diagnostic #:dc-live-diagnostic
   #:dc-regression-endpoints #:dc-new-drifts #:dc-resolved-drifts
   #:dc-compatible-p #:dc-summary
   #:compare-snapshot-drifts
   #:snapshot-drift-diagnostic-to-json #:drift-comparison-to-json
   ;; Runtime transport (q8l)
   #:transport-method #:retry-strategy #:transport-outcome-status
   #:retry-policy #:retry-policy-p #:make-retry-policy
   #:rp-max-attempts #:rp-strategy #:rp-base-delay-ms #:rp-max-delay-ms
   #:rp-retryable-codes
   #:*default-retry-policy* #:*no-retry-policy*
   #:transport-request #:transport-request-p #:make-transport-request
   #:treq-method #:treq-url #:treq-headers #:treq-timeout-ms #:treq-body
   #:transport-response #:transport-response-p #:make-transport-response
   #:tresp-status-code #:tresp-body #:tresp-headers #:tresp-latency-ms
   #:transport-attempt #:transport-attempt-p #:make-transport-attempt
   #:ta-attempt-number #:ta-response #:ta-error-class #:ta-error-message
   #:ta-delay-before-ms
   #:transport-outcome #:transport-outcome-p #:make-transport-outcome
   #:tout-status #:tout-response #:tout-attempts #:tout-total-ms #:tout-request
   #:compute-delay #:retryable-status-p #:retryable-attempt-p
   #:map-status-class #:outcome-status-to-error-class
   #:outcome-to-sample
   #:execute-transport
   #:make-fixture-transport #:make-dexador-transport
   #:target-endpoint-request
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
   #:gen-regression-corpus))

(defpackage #:orrery/adapter/openclaw
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record
                #:history-entry
                #:cron-record
                #:health-record
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
   #:openclaw-transport-error
   #:openclaw-decode-error
   #:openclaw-fetch-sessions
   #:openclaw-fetch-cron-jobs
   #:openclaw-fetch-health
   #:openclaw-decode-sessions
   #:openclaw-decode-cron-jobs
   #:openclaw-decode-health
   ;; Live endpoint contract probe
   #:probe-mismatch #:probe-mismatch-p #:make-probe-mismatch
   #:probe-mismatch-endpoint #:probe-mismatch-category #:probe-mismatch-detail
   #:probe-endpoint-result #:probe-endpoint-result-p #:make-probe-endpoint-result
   #:probe-endpoint-result-endpoint #:probe-endpoint-result-ok-p
   #:probe-endpoint-result-http-status #:probe-endpoint-result-content-type
   #:probe-endpoint-result-json-p #:probe-endpoint-result-mismatches
   #:probe-report #:probe-report-p #:make-probe-report
   #:probe-report-base-url #:probe-report-overall-ok-p #:probe-report-results
   #:openclaw-live-contract-probe
   #:%openclaw-request
   ;; HTML fallback (sy2)
   #:remediation-hint #:remediation-hint-p #:make-remediation-hint
   #:rh-endpoint #:rh-problem #:rh-suggestion #:rh-alternative-url
   #:fallback-result #:fallback-result-p #:make-fallback-result
   #:fb-usable-p #:fb-original-url #:fb-resolved-url #:fb-hints
   #:detect-content-kind #:evaluate-endpoint-fallback #:evaluate-all-endpoints
   ;; Capability mapper (8oo)
   #:command-request #:command-request-p #:make-command-request
   #:cmd-req-kind #:cmd-req-target-id #:cmd-req-params
   #:command-response #:command-response-p #:make-command-response
   #:cmd-res-kind #:cmd-res-ok-p #:cmd-res-result #:cmd-res-error-detail
   #:capability-gate #:capability-gate-p #:make-capability-gate
   #:cg-allowed-ops #:cg-denied-ops
   #:operation-denied
   #:build-capability-gate #:operation-allowed-p #:safe-execute
   ;; Endpoint classifier (1t2)
   #:endpoint-classification #:endpoint-classification-p #:make-endpoint-classification
   #:ec-path #:ec-surface #:ec-http-status #:ec-content-type #:ec-body-shape #:ec-confidence
   #:classify-endpoint-response #:detect-body-shape
   ;; Handshake probe (bq1)
   #:handshake-result #:handshake-result-p #:make-handshake-result
   #:hs-base-url #:hs-family #:hs-ready-p #:hs-classification #:hs-remediation
   #:handshake-report #:handshake-report-p #:make-handshake-report
   #:hr-results #:hr-overall-ready-p #:hr-summary
   #:classify-response-family #:make-family-remediation #:run-handshake-probe))

(defpackage #:orrery/coalton/core
  (:use #:coalton #:coalton-prelude)
  (:export
   #:normalize-status-code
   #:estimate-cost-cents
   ;; Policy algebra (fhk)
   #:PolicyDecision #:Allow #:Deny #:Ask
   #:PolicyRule #:PolicySet
   #:rule-operation #:rule-decision
   #:combine-decisions #:evaluate-policy #:merge-policies
   #:decision-permits-p #:make-policy
   ;; Configuration schema/defaults (1oe)
   #:ConnectionConfig #:connectionconfig #:cc-host #:cc-port #:cc-token
   #:UiConfig #:uiconfig #:ui-theme #:ui-refresh-seconds #:ui-compact-mode
   #:FeatureFlags #:featureflags #:ff-web-enabled #:ff-tui-enabled #:ff-mcclim-enabled
   #:RuntimeConfig #:runtimeconfig
   #:rc-connection #:rc-ui #:rc-polling-seconds
   #:rc-budget-warning-cents #:rc-budget-critical-cents #:rc-flags
   #:default-connection-config #:default-ui-config #:default-feature-flags #:default-runtime-config
   #:pick-string #:pick-positive
   #:merge-connection-config #:merge-ui-config #:merge-feature-flags #:merge-runtime-config
   #:valid-theme-p #:validate-runtime-config
   #:config-valid-p #:config-error-count #:config-first-error
   ;; Configuration CL bridge
   #:cl-default-runtime-config #:cl-make-runtime-config #:cl-merge-runtime-config
   #:cl-config-valid-p #:cl-config-error-count #:cl-config-first-error
   #:cl-config-host #:cl-config-port #:cl-config-theme #:cl-config-polling-seconds
   #:cl-config-budget-warning-cents #:cl-config-budget-critical-cents
   #:cl-config-web-enabled-p #:cl-config-tui-enabled-p #:cl-config-mcclim-enabled-p
   ;; Usage analytics (68i)
   #:UsageEntry #:usageentry
   #:ue-model #:ue-prompt-tokens #:ue-completion-tokens #:ue-timestamp
   #:ue-total-tokens #:ue-cost-cents
   #:ModelRank #:modelrank #:mr-model #:mr-total-tokens #:mr-permille
   #:UsageBucket #:usagebucket
   #:bucket-period #:bucket-entries #:bucket-total-tokens #:bucket-total-cost
   #:aggregate-entries #:sum-tokens #:sum-cost #:top-models
   #:UsageSummary #:usagesummary
   #:summary-buckets #:summary-top-models #:summary-total-tokens #:summary-total-cost
   #:build-usage-summary
   ;; CL-callable bridge functions
   #:cl-make-usage-entry #:cl-make-entry-list
   #:cl-aggregate-entries #:cl-build-summary
   #:cl-summary-total-tokens #:cl-summary-total-cost #:cl-summary-top-models
   #:cl-make-model-rank
   ;; Anomaly detector (mhg)
   #:AnomalySeverity #:AnomalyNone #:AnomalyWarning #:AnomalyCritical
   #:AnomalyKind #:SessionCountDrift #:CostRunaway #:TokenSpikeDetected
   #:ModelRoutingShift #:AdapterDivergence
   #:AnomalyFinding #:anomalyfinding
   #:af-kind #:af-severity #:af-description #:af-observed #:af-baseline #:af-score
   #:AnomalyReport #:anomalyreport
   #:ar-findings #:ar-worst-severity #:ar-anomaly-count #:ar-risk-score
   #:AnomalyThresholds #:anomalythresholds
   #:at-session-warn #:at-session-crit #:at-cost-warn #:at-cost-crit
   #:at-token-warn #:at-token-crit #:at-model-warn #:at-model-crit
   #:default-thresholds #:deviation-permille #:classify-deviation
   #:detect-session-drift #:detect-cost-runaway #:detect-token-spike
   #:detect-model-shift #:detect-adapter-divergence
   #:compute-risk-score #:build-anomaly-report #:run-anomaly-pipeline
   #:cl-default-thresholds #:cl-deviation-permille
   #:cl-detect-session-drift #:cl-detect-cost-runaway #:cl-detect-token-spike
   #:cl-detect-adapter-divergence #:cl-run-anomaly-pipeline
   #:cl-anomaly-report-count #:cl-anomaly-report-risk-score #:cl-anomaly-report-findings
   #:cl-finding-list-count #:cl-anomaly-report-worst-severity-label
   #:cl-anomaly-severity-label #:cl-anomaly-kind-label
   ;; Budget policy (2ya)
   #:BudgetPeriod #:BPDaily #:BPWeekly #:BPMonthly
   #:BudgetScope #:GlobalScope #:ModelScope #:SessionScope
   #:BudgetLimit #:budgetlimit #:bl-scope #:bl-period #:bl-max-tokens #:bl-max-cost
   #:ThresholdLevel #:TLOk #:TLWarning #:TLCritical #:TLExceeded
   #:BudgetVerdict #:budgetverdict #:bv-scope #:bv-level #:bv-actual
   #:bv-limit-tokens #:bv-utilization
   #:classify-threshold #:evaluate-limit #:evaluate-policy-limits
   #:worst-level #:verdict-hint
   ;; Budget CL bridge
   #:cl-make-budget-limit #:cl-evaluate-policy
   #:cl-verdict-level-keyword #:cl-verdict-hint
   #:cl-verdict-utilization #:cl-verdict-actual
   ;; Notification routing (78i)
   #:AlertSeverity #:SeverityInfo #:SeverityWarning #:SeverityCritical
   #:AckLifecycle #:AckNone #:AckPending #:AckAcknowledged #:AckSnoozed
   #:DeliveryChannel #:ChannelTuiOverlay #:ChannelWebToast #:ChannelMcclimPane
   #:NotificationEvent #:notificationevent
   #:ne-id #:ne-severity #:ne-title #:ne-source #:ne-fired-at #:ne-ack-state
   #:DispatcherConfig #:dispatcherconfig
   #:dc-tui-enabled #:dc-web-enabled #:dc-mcclim-enabled #:dc-dedupe-enabled #:dc-ack-threshold
   #:RouteDecision #:routedecision
   #:rd-dedup-key #:rd-channels #:rd-suppressed-duplicate-p #:rd-requires-ack-p #:rd-reason
   #:default-dispatcher-config
   #:severity-score #:classify-severity #:severity-label #:ack-label #:channel-label
   #:event-dedup-key #:string-member-p #:append-if #:choose-channels
   #:dispatch-notification #:dispatch-batch
   ;; Notification routing CL bridge
   #:cl-severity-from-keyword #:cl-ack-from-keyword
   #:cl-default-dispatcher-config #:cl-make-dispatcher-config
   #:cl-make-notification-event #:cl-dispatch-notification
   #:cl-route-dedup-key #:cl-route-suppressed-p #:cl-route-requires-ack-p
   #:cl-route-reason #:cl-route-channel-keywords
   ;; Session lifecycle (q8r)
   #:SessionState #:SessionCreating #:SessionActive #:SessionIdle
   #:SessionClosing #:SessionClosed #:SessionError
   #:TransitionEvent #:EvInitialized #:EvMessageReceived #:EvIdleTimeout
   #:EvShutdownRequested #:EvShutdownComplete #:EvFatalError #:EvRestart
   #:TransitionResult #:TransitionOk #:TransitionDenied
   #:session-state-terminal-p #:session-state-alive-p
   #:session-state-label #:transition-event-label
   #:transition #:validate-transition-sequence
   #:count-valid-transitions
   #:happy-path-events #:error-path-events
   ;; Scenario planning (20d)
   #:ScenarioParam #:SPSessionVolume #:SPModelMix #:SPCronCadence
   #:SPBudgetCap #:SPTokenCeiling #:sp-tag
   #:Scenario #:scenario-name #:scenario-params #:scenario-horizon
   #:BaselineSnapshot #:bs-sessions #:bs-tokens-per-hour #:bs-cost-per-hour
   #:bs-cron-per-hour #:bs-model-mix #:bs-budget-cap
   #:ProjectionSignal #:SignalOk #:SignalCaution #:SignalOverBudget
   #:SignalOverCapacity #:SignalMixImbalance #:signal-label
   #:ProjectionResult #:pr-scenario-name #:pr-total-tokens #:pr-total-cost
   #:pr-sessions #:pr-cron-invocations #:pr-budget-util-pct #:pr-signals
   #:run-scenario #:run-scenarios
   ;; Scenario planning CL bridge
   #:cl-make-baseline-snapshot #:cl-make-scenario
   #:cl-sp-session-volume #:cl-sp-budget-cap #:cl-sp-token-ceiling
   #:cl-sp-cron-cadence #:cl-sp-model-mix
   #:cl-run-scenario #:cl-run-scenarios
   #:cl-projection-scenario-name #:cl-projection-total-tokens
   #:cl-projection-total-cost #:cl-projection-sessions
   #:cl-projection-cron-invocations #:cl-projection-budget-util-pct
   #:cl-projection-signal-labels
   ;; Audit trail (8cn)
   #:AuditCategory #:AuditSessionLifecycle #:AuditCronExecution
   #:AuditPolicyChange #:AuditConfigChange #:AuditAlertFired
   #:AuditGateDecision #:AuditModelRouting #:AuditAdapterEvent
   #:AuditManualAction #:audit-category-label
   #:AuditSeverity #:AuditTrace #:AuditInfo #:AuditWarning #:AuditCritical
   #:audit-severity-label #:audit-severity-score
   #:AuditHash #:audit-hash-value #:genesis-hash
   #:AuditEntry #:ae-seq #:ae-timestamp #:ae-category #:ae-severity
   #:ae-actor #:ae-summary #:ae-detail #:ae-hash #:ae-prev-hash
   #:AuditTrail #:trail-count #:trail-entries #:trail-tip-hash
   #:empty-trail #:hash-input #:make-audit-entry #:append-entry
   #:verify-chain-link #:verify-trail
   #:filter-by-category #:filter-by-severity-min #:filter-by-time-range
   #:trail-latest #:count-by-severity
   ;; Audit trail CL bridge
   #:cl-empty-trail #:cl-append-entry #:cl-verify-trail
   #:cl-trail-count #:cl-trail-tip-hash
   #:cl-audit-session-lifecycle #:cl-audit-cron-execution
   #:cl-audit-policy-change #:cl-audit-config-change
   #:cl-audit-alert-fired #:cl-audit-gate-decision
   #:cl-audit-model-routing #:cl-audit-adapter-event
   #:cl-audit-manual-action
   #:cl-audit-trace #:cl-audit-info #:cl-audit-warning #:cl-audit-critical
   #:cl-make-single-entry
   #:cl-entry-seq #:cl-entry-timestamp #:cl-entry-category-label
   #:cl-entry-severity-label #:cl-entry-actor #:cl-entry-summary
   #:cl-entry-detail #:cl-entry-hash #:cl-entry-prev-hash
   #:cl-filter-by-category #:cl-filter-by-severity-min #:cl-count-by-severity
   ;; Cost optimizer (nhh)
   #:ModelCostProfile #:mcp-name #:mcp-prompt-cost #:mcp-completion-cost
   #:mcp-quality #:mcp-latency
   #:OptimizationStrategy #:OptCost #:OptQuality #:OptBalanced #:OptLatency
   #:strategy-label
   #:RouteConfidence #:ConfHigh #:ConfMedium #:ConfLow
   #:confidence-score #:confidence-label
   #:RouteRecommendation #:rr-model #:rr-reason #:rr-savings-pct
   #:rr-confidence #:rr-strategy
   #:CostAnalysis #:ca-current-cost #:ca-optimal-cost #:ca-savings-pct
   #:ca-recommendations #:ca-strategy
   #:recommend-model #:analyze-cost
   ;; Cost optimizer CL bridge
   #:cl-make-model-cost-profile
   #:cl-opt-cost #:cl-opt-quality #:cl-opt-balanced #:cl-opt-latency
   #:cl-recommend-model #:cl-analyze-cost
   #:cl-rr-model #:cl-rr-reason #:cl-rr-savings-pct
   #:cl-rr-confidence-label #:cl-rr-strategy-label
   #:cl-ca-current-cost #:cl-ca-optimal-cost #:cl-ca-savings-pct
   #:cl-ca-strategy-label #:cl-ca-recommendations
   ;; Capacity planner (j9c)
   #:CapacityZone #:ZoneIdle #:ZoneNormal #:ZoneCaution #:ZoneCritical #:ZoneOverflow
   #:zone-label #:zone-severity
   #:ThresholdSpec #:ts-metric #:ts-warning #:ts-critical #:ts-maximum
   #:CapacityAssessment #:assess-metric #:assess-value #:assess-zone
   #:assess-headroom #:assess-util-pct #:assess-recommendation
   #:CapacityPlan #:plan-assessments #:plan-worst-zone #:plan-headroom-pct
   #:classify-zone #:evaluate-threshold #:build-capacity-plan
   #:default-capacity-thresholds
   ;; Capacity planner CL bridge
   #:cl-make-threshold-spec #:cl-default-capacity-thresholds
   #:cl-evaluate-threshold #:cl-build-capacity-plan
   #:cl-assess-metric-name #:cl-assess-value #:cl-assess-zone-label
   #:cl-assess-headroom #:cl-assess-util-pct #:cl-assess-recommendation
   #:cl-plan-worst-zone-label #:cl-plan-headroom-pct #:cl-plan-assessments
   ;; Session analytics (3jv)
   #:SessionMetric #:sm-id #:sm-duration #:sm-tokens #:sm-messages #:sm-cost #:sm-model
   #:EfficiencyMetrics #:em-id #:em-tokens-per-message #:em-tokens-per-minute
   #:em-cost-per-1k #:em-messages-per-min-x100
   #:DurationBucket #:db-label #:db-lower #:db-upper #:db-count
   #:SessionAnalyticsSummary #:sas-total #:sas-avg-duration #:sas-median-tokens
   #:sas-avg-tokens-per-msg #:sas-total-cost #:sas-duration-buckets #:sas-efficiency
   #:compute-efficiency #:build-duration-distribution #:analyze-sessions
   ;; Session analytics CL bridge
   #:cl-make-session-metric #:cl-compute-efficiency #:cl-analyze-sessions
   #:cl-em-id #:cl-em-tokens-per-message #:cl-em-tokens-per-minute #:cl-em-cost-per-1k
   #:cl-sas-total #:cl-sas-avg-duration #:cl-sas-median-tokens
   #:cl-sas-avg-tokens-per-msg #:cl-sas-total-cost
   #:cl-sas-duration-buckets #:cl-sas-efficiency
   #:cl-db-label #:cl-db-count))

(defpackage #:orrery/pipeline
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:make-session-record
                #:event-record #:event-record-p #:make-event-record
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
   #:project-usage-summary #:project-activity-feed #:project-alert-state
   ;; Typed snapshot/event normalization
   #:normalized-snapshot #:normalized-snapshot-p #:make-normalized-snapshot
   #:normalized-snapshot-sessions #:normalized-snapshot-events
   #:normalized-snapshot-alerts #:normalized-snapshot-sync-token
   #:normalize-timestamp
   #:normalize-session-payload #:normalize-event-payload #:normalize-alert-payload
   #:normalize-snapshot-payload))

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

(defpackage #:orrery/provider
  (:use #:cl)
  (:import-from #:orrery/domain
                #:session-record #:session-record-p
                #:sr-id #:sr-agent-name #:sr-channel #:sr-status #:sr-model
                #:sr-created-at #:sr-updated-at #:sr-message-count
                #:sr-total-tokens #:sr-estimated-cost-cents
                #:cron-record #:cron-record-p
                #:cr-name #:cr-kind #:cr-interval-s #:cr-status
                #:cr-last-run-at #:cr-next-run-at #:cr-run-count
                #:cr-last-error #:cr-description
                #:health-record #:health-record-p
                #:hr-component #:hr-status #:hr-message #:hr-checked-at #:hr-latency-ms
                #:usage-record #:usage-record-p
                #:ur-model #:ur-period #:ur-timestamp
                #:ur-prompt-tokens #:ur-completion-tokens #:ur-total-tokens
                #:ur-estimated-cost-cents
                #:event-record #:event-record-p
                #:er-id #:er-kind #:er-source #:er-message #:er-timestamp #:er-metadata
                #:alert-record #:alert-record-p
                #:ar-id #:ar-severity #:ar-title #:ar-message #:ar-source
                #:ar-fired-at #:ar-acknowledged-p #:ar-snoozed-until
                #:subagent-record #:subagent-record-p
                #:sar-id #:sar-parent-session #:sar-agent-name #:sar-status
                #:sar-started-at #:sar-finished-at #:sar-total-tokens #:sar-result)
  (:import-from #:orrery/store
                #:sync-store #:sync-store-p
                #:ss-sessions #:ss-cron-jobs #:ss-health #:ss-usage
                #:ss-events #:ss-alerts #:ss-subagents
                #:ss-last-sync-at #:ss-sync-token)
  (:export
   ;; Page container
   #:page #:page-p #:make-page #:copy-page
   #:page-items #:page-offset #:page-limit #:page-total
   ;; Sort spec
   #:sort-spec #:sort-spec-p #:make-sort-spec #:copy-sort-spec
   #:sort-spec-key #:sort-spec-direction
   ;; Filter spec
   #:filter-spec #:filter-spec-p #:make-filter-spec #:copy-filter-spec
   #:filter-spec-field #:filter-spec-op #:filter-spec-value
   ;; Session view
   #:session-view #:session-view-p #:make-session-view #:copy-session-view
   #:sv-record #:sv-age-seconds #:sv-cost-display #:sv-token-display
   ;; Cron view
   #:cron-view #:cron-view-p #:make-cron-view #:copy-cron-view
   #:cv-record #:cv-overdue-p #:cv-error-p #:cv-interval-display
   ;; Health view
   #:health-view #:health-view-p #:make-health-view #:copy-health-view
   #:hv-record #:hv-ok-p #:hv-latency-display
   ;; Event view
   #:event-view #:event-view-p #:make-event-view #:copy-event-view
   #:ev-record #:ev-age-seconds #:ev-severity-indicator
   ;; Alert view
   #:alert-view #:alert-view-p #:make-alert-view #:copy-alert-view
   #:alv-record #:alv-active-p #:alv-age-seconds #:alv-urgency
   ;; Usage view
   #:usage-view #:usage-view-p #:make-usage-view #:copy-usage-view
   #:uv-record #:uv-cost-display #:uv-token-display
   ;; Dashboard summary
   #:dashboard-summary #:dashboard-summary-p #:make-dashboard-summary
   #:copy-dashboard-summary
   #:ds-session-count #:ds-active-session-count
   #:ds-cron-count #:ds-overdue-cron-count
   #:ds-health-ok-p #:ds-degraded-components
   #:ds-alert-count #:ds-critical-alert-count
   #:ds-total-tokens #:ds-total-cost-cents
   #:ds-last-sync-at
   ;; Query functions — pure transforms
   #:query-sessions #:query-cron-jobs #:query-health
   #:query-events #:query-alerts #:query-usage
   #:build-dashboard-summary #:dashboard-summary-ui-message
   ;; Display helpers
   #:format-tokens #:format-cost-cents #:format-age
   #:format-interval))


