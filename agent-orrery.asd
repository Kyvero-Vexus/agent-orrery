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
      :components ((:file "core")))))))

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
                   (:file "openclaw")))
     (:module "pipeline"
      :components ((:file "events")))
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
                   (:file "coalton-core-tests")))))))
