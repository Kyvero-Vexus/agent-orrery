;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; packages.lisp — Plugin SDK packages
;;; Bead: agent-orrery-eb0.6.1

(defpackage #:orrery/plugin
  (:use #:cl)
  (:export
   ;; Plugin protocol
   #:plugin #:plugin-name #:plugin-version #:plugin-description
   #:plugin-card-definitions #:plugin-command-definitions
   #:plugin-transformer-definitions
   ;; Card protocol
   #:card-definition #:make-card-definition
   #:cd-name #:cd-title #:cd-renderer #:cd-data-fn #:cd-priority
   ;; Command protocol
   #:command-definition #:make-command-definition
   #:cmd-name #:cmd-handler #:cmd-description #:cmd-keystroke
   ;; Transformer protocol
   #:transformer-definition #:make-transformer-definition
   #:td-name #:td-input-type #:td-output-type #:td-transform-fn
   ;; Registry
   #:*plugin-registry* #:register-plugin #:unregister-plugin
   #:find-plugin #:list-plugins
   #:all-card-definitions #:all-command-definitions
   #:all-transformer-definitions
   ;; Validation
   #:validate-plugin #:plugin-validation-result
   ;; v2 Lifecycle hooks (a3p)
   #:hook-phase
   #:lifecycle-hook #:lifecycle-hook-p #:make-lifecycle-hook
   #:lh-name #:lh-module #:lh-phase #:lh-handler #:lh-priority
   #:plugin-lifecycle-hooks
   #:plugin-on-audit-event #:plugin-on-cost-recommendation
   #:plugin-on-capacity-assessment #:plugin-on-session-analytics
   #:plugin-on-scenario-projection
   #:dispatch-lifecycle-hooks
   #:make-plugin-validation-result
   #:pvr-valid-p #:pvr-errors #:pvr-warnings
   ;; Conformance corpus + runner (bmc)
   #:conformance-verdict
   #:plugin-conformance-case #:make-plugin-conformance-case
   #:pcc-case-id #:pcc-plugin-name #:pcc-plugin-version #:pcc-description
   #:pcc-cards #:pcc-commands #:pcc-transformers
   #:pcc-expected-valid-p #:pcc-expected-error-fragments #:pcc-expected-warning-fragments
   #:pcc-compat-tags
   #:plugin-conformance-result #:make-plugin-conformance-result
   #:pcr-case-id #:pcr-verdict #:pcr-actual-valid-p #:pcr-errors #:pcr-warnings
   #:pcr-compat-findings #:pcr-summary
   #:plugin-conformance-report #:make-plugin-conformance-report
   #:pcrep-suite-id #:pcrep-seed #:pcrep-generated-at #:pcrep-total #:pcrep-passed
   #:pcrep-failed #:pcrep-results
   #:strict-schema-checks #:compatibility-checks
   #:run-plugin-contract #:run-conformance-case
   #:make-default-plugin-conformance-corpus #:run-plugin-conformance-corpus
   #:deterministic-conformance-command
   #:conformance-result->json #:conformance-report->json))
