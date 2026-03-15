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
   #:adapter-not-found-id
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
   #:health-status #:probe-domain #:gate-verdict
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
   #:decision-permits-p #:make-policy))

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
