;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; agent-orrery.asd — System definitions for Agent Orrery
;;;

(defsystem "agent-orrery"
  :description "Dashboard for OpenClaw-compatible agent systems"
  :version "0.1.0"
  :license "MIT"
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:module "domain"
      :components ((:file "types")))
     (:module "adapter"
      :components ((:file "protocol")))))))

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
     (:file "fixture-adapter")
     (:module "tests"
      :components ((:file "harness-tests")))))))
