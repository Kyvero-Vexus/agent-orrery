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
                   (:file "policy")))))))

(defsystem "agent-orrery"
  :description "Dashboard for OpenClaw-compatible agent systems"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("agent-orrery/coalton" "dexador" "com.inuoe.jzon")
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
                   (:file "schema-drift")))
     (:module "pipeline"
      :components ((:file "events")
                   (:file "normalize")))
     (:module "store"
      :components ((:file "sync")))))))

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
                   (:file "pipeline-store-tests")
                   (:file "conformance-tests")
                   (:file "contract-probe-tests")
                   (:file "normalization-tests")
                   (:file "coalton-core-tests")
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
                   (:file "schema-drift-tests")))))))
