;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; agent-orrery.asd — System definitions for Agent Orrery
;;;

(defsystem "agent-orrery/coalton"
  :description "Coalton pure-core baseline for Agent Orrery"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("coalton" "named-readtables")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:module "coalton"
      :serial t
      :components ((:file "core")
                   (:file "policy")
                   (:file "configuration")
                   (:file "usage-analytics")
                   (:file "anomaly-detector")
                   (:file "budget-policy")
                   (:file "session-lifecycle")))))))

(defsystem "agent-orrery"
  :description "Dashboard for OpenClaw-compatible agent systems"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("agent-orrery/coalton" "dexador" "com.inuoe.jzon" "croatoan" "hunchentoot" "mcclim")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:module "domain"
      :components ((:file "types")))
     (:module "adapter"
      :components ((:file "protocol")
                   (:file "generic-starter-kit")
                   (:file "openclaw")
                   (:file "contract-probe")
                   (:file "html-fallback")
                   (:file "capability-mapper")
                   (:file "endpoint-classifier")
                   (:file "handshake-probe")
                   (:file "capability-contract")
                   (:file "preflight")
                   (:file "gate-runner")
                   (:file "preflight-json")
                   (:file "contract-harness")
                   (:file "probe-orchestrator")
                   (:file "compatibility-report")
                   (:file "conformance-matrix")
                   (:file "transcript-capture")
                   (:file "schema-drift")
                   (:file "evidence-bundle")
                   (:file "gate-decision")
                   (:file "gate-orchestrator")
                   (:file "interface-matrix")
                   (:file "decision-core")
                   (:file "schema-compat")
                   (:file "replay-harness")
                   (:file "gate-invariant")
                   (:file "schema-gen")
                   (:file "replay-artifact")
                   (:file "runtime-transport")
                   (:file "capture-driver")
                   (:file "fixture-replay-compiler")
                   (:file "evidence-pack")
                   (:file "snapshot-drift")
                   (:file "health-monitor")
                   (:file "capture-differ")
                   (:file "decision-audit")
                   (:file "action-intent")
                   (:file "event-trace-canon")
                   (:file "parity-assertion")
                   (:file "fixture-corpus-gen")
                   (:file "gate-orchestration-runner")
                   (:file "usage-analytics-bridge")
                   (:file "anomaly-detector")
                   (:file "observability-trace-contract")
                   (:file "cross-ui-evidence-verifier")
                   (:file "cross-ui-parity-suite")))
     (:module "pipeline"
      :components ((:file "events")
                   (:file "normalize")))
     (:module "store"
      :components ((:file "sync")))
     (:module "provider"
      :components ((:file "tui")))
     (:module "tui"
      :serial t
      :components ((:file "packages")
                   (:file "layout")
                   (:file "keys")
                   (:file "state")
                   (:file "render")
                   (:file "session-detail")
                   (:file "cron-ops")
                   (:file "analytics")
                   (:file "shell")))
     (:module "web"
      :serial t
      :components ((:file "packages")
                   (:file "views")
                   (:file "api")
                   (:file "server")))
     (:module "plugin"
      :serial t
      :components ((:file "packages")
                   (:file "sdk")
                   (:file "conformance")))
     (:module "mcclim"
      :serial t
      :components ((:file "packages")
                   (:file "frame")
                   (:file "commands")
                   (:file "inspectors")
                   (:file "e2e-gate")))))))

(defsystem "agent-orrery/test-harness"
  :description "Deterministic fixture runtime harness for Agent Orrery"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("agent-orrery" "parachute")
  :serial t
  :components
  ((:module "test-harness"
    :serial t
    :components
    ((:file "packages")
     (:file "clock")
     (:file "timeline")
     (:file "generators")
     (:file "conformance")
     (:file "fixture-adapter")
     (:module "tests"
      :components ((:file "harness-tests")
                   (:file "openclaw-adapter-tests")
                   (:file "generic-starter-kit-tests")
                   (:file "pipeline-store-tests")
                   (:file "conformance-tests")
                   (:file "contract-probe-tests")
                   (:file "normalization-tests")
                   (:file "coalton-core-tests")
                   (:file "configuration-tests")
                   (:file "html-fallback-tests")
                   (:file "capability-mapper-tests")
                   (:file "endpoint-classifier-tests")
                   (:file "policy-algebra-tests")
                   (:file "handshake-probe-tests")
                   (:file "policy-law-checks")
                   (:file "../fixtures/live-gate-corpus")
                   (:file "live-gate-contract-tests")
                   (:file "capability-contract-tests")
                   (:file "preflight-tests")
                   (:file "contract-harness-tests")
                   (:file "probe-orchestrator-tests")
                   (:file "conformance-matrix-tests")
                   (:file "transcript-capture-tests")
                   (:file "schema-drift-tests")
                   (:file "evidence-bundle-tests")
                   (:file "gate-decision-tests")
                   (:file "gate-orchestrator-tests")
                   (:file "interface-matrix-tests")
                   (:file "decision-core-tests")
                   (:file "schema-compat-tests")
                   (:file "replay-harness-tests")
                   (:file "gate-invariant-tests")
                   (:file "schema-gen-tests")
                   (:file "replay-artifact-tests")
                   (:file "runtime-transport-tests")
                   (:file "capture-driver-tests")
                   (:file "fixture-replay-compiler-tests")
                   (:file "evidence-pack-tests")
                   (:file "snapshot-drift-tests")
                   (:file "health-monitor-tests")
                   (:file "capture-differ-tests")
                   (:file "decision-audit-tests")
                   (:file "usage-analytics-tests")
                   (:file "anomaly-detector-tests")
                   (:file "plugin-sdk-tests")
                   (:file "plugin-conformance-tests")
                   (:file "budget-policy-tests")
                   (:file "event-trace-canon-tests")
                   (:file "parity-assertion-tests")
                   (:file "fixture-corpus-gen-tests")
                   (:file "gate-orchestration-runner-tests")
                   (:file "action-intent-tests")
                   (:file "tui-provider-tests")
                   (:file "tui-session-detail-tests")
                   (:file "tui-shell-tests")
                   (:file "session-lifecycle-tests")
                   (:file "tui-cron-ops-tests")
                   (:file "tui-analytics-tests")
                   (:file "mcclim-frame-tests")
                   (:file "mcclim-commands-tests")
                   (:file "mcclim-inspectors-tests")
                   (:file "mcclim-accessibility-tests")
                   (:file "mcclim-e2e-gate-tests")
                   (:file "observability-trace-contract-tests")
                   (:file "cross-ui-evidence-verifier-tests")
                   (:file "cross-ui-parity-suite-tests")))))))
