;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; scenario-planning-bridge.lisp — CL adapter for scenario projections
;;;
;;; Bead: agent-orrery-20d

(in-package #:orrery/adapter)

(defstruct (scenario-projection (:conc-name sproj-))
  "CL-side scenario projection result."
  (scenario-name "" :type string)
  (total-tokens 0 :type integer)
  (total-cost 0 :type integer)
  (sessions 0 :type integer)
  (cron-invocations 0 :type integer)
  (budget-util-pct 0 :type integer)
  (signals nil :type list))

(declaim
 (ftype (function (t) (values scenario-projection &optional)) coalton-projection->cl)
 (ftype (function (scenario-projection) (values string &optional)) scenario-projection->json))

(defun coalton-projection->cl (coalton-result)
  "Convert a Coalton ProjectionResult to CL scenario-projection struct."
  (declare (optimize (safety 3)))
  (make-scenario-projection
   :scenario-name (orrery/coalton/core:cl-projection-scenario-name coalton-result)
   :total-tokens (orrery/coalton/core:cl-projection-total-tokens coalton-result)
   :total-cost (orrery/coalton/core:cl-projection-total-cost coalton-result)
   :sessions (orrery/coalton/core:cl-projection-sessions coalton-result)
   :cron-invocations (orrery/coalton/core:cl-projection-cron-invocations coalton-result)
   :budget-util-pct (orrery/coalton/core:cl-projection-budget-util-pct coalton-result)
   :signals (orrery/coalton/core:cl-projection-signal-labels coalton-result)))

(defun scenario-projection->json (proj)
  "Deterministic JSON emitter."
  (declare (type scenario-projection proj) (optimize (safety 3)))
  (format nil "{\"scenario\":\"~A\",\"total_tokens\":~D,\"total_cost_cents\":~D,\"sessions\":~D,\"cron_invocations\":~D,\"budget_util_pct\":~D,\"signals\":[~{\"~A\"~^,~}]}"
          (sproj-scenario-name proj)
          (sproj-total-tokens proj)
          (sproj-total-cost proj)
          (sproj-sessions proj)
          (sproj-cron-invocations proj)
          (sproj-budget-util-pct proj)
          (sproj-signals proj)))
