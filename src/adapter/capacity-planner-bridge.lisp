;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capacity-planner-bridge.lisp — CL adapter for Coalton capacity planning
;;;
;;; Bead: agent-orrery-93ec

(in-package #:orrery/adapter)

;;; CL-side struct for capacity assessment
(defstruct (capacity-assessment-record (:conc-name cpar-))
  "CL-side capacity assessment for one metric."
  (metric "" :type string)
  (value 0 :type integer)
  (zone "" :type string)
  (headroom 0 :type integer)
  (util-pct 0 :type integer)
  (recommendation "" :type string))

;;; CL-side struct for full capacity plan
(defstruct (capacity-plan-record (:conc-name cpr-))
  "CL-side capacity plan with all assessments."
  (assessments nil :type list)
  (worst-zone "" :type string)
  (headroom-pct 0 :type integer))

(declaim
 (ftype (function (t) (values capacity-assessment-record &optional)) coalton-assessment->cl)
 (ftype (function (t) (values capacity-plan-record &optional)) coalton-plan->cl)
 (ftype (function (capacity-assessment-record) (values string &optional)) capacity-assessment->json)
 (ftype (function (capacity-plan-record) (values string &optional)) capacity-plan->json))

(defun coalton-assessment->cl (coalton-assess)
  "Convert a Coalton CapacityAssessment to CL capacity-assessment-record."
  (declare (optimize (safety 3)))
  (make-capacity-assessment-record
   :metric (orrery/coalton/core:cl-assess-metric-name coalton-assess)
   :value (orrery/coalton/core:cl-assess-value coalton-assess)
   :zone (orrery/coalton/core:cl-assess-zone-label coalton-assess)
   :headroom (orrery/coalton/core:cl-assess-headroom coalton-assess)
   :util-pct (orrery/coalton/core:cl-assess-util-pct coalton-assess)
   :recommendation (orrery/coalton/core:cl-assess-recommendation coalton-assess)))

(defun coalton-plan->cl (coalton-plan)
  "Convert a Coalton CapacityPlan to CL capacity-plan-record."
  (declare (optimize (safety 3)))
  (let ((assessments (orrery/coalton/core:cl-plan-assessments coalton-plan)))
    (make-capacity-plan-record
     :assessments (mapcar #'coalton-assessment->cl assessments)
     :worst-zone (orrery/coalton/core:cl-plan-worst-zone-label coalton-plan)
     :headroom-pct (orrery/coalton/core:cl-plan-headroom-pct coalton-plan))))

(defun capacity-assessment->json (assess)
  "Deterministic JSON emitter for capacity assessment."
  (declare (type capacity-assessment-record assess) (optimize (safety 3)))
  (format nil "{\"metric\":\"~A\",\"value\":~D,\"zone\":\"~A\",\"headroom\":~D,\"util_pct\":~D,\"recommendation\":\"~A\"}"
          (cpar-metric assess)
          (cpar-value assess)
          (cpar-zone assess)
          (cpar-headroom assess)
          (cpar-util-pct assess)
          (cpar-recommendation assess)))

(defun capacity-plan->json (plan)
  "Deterministic JSON emitter for capacity plan."
  (declare (type capacity-plan-record plan) (optimize (safety 3)))
  (let ((assessments-json (format nil "[~{~A~^,~}]"
                                   (mapcar #'capacity-assessment->json (cpr-assessments plan)))))
    (format nil "{\"assessments\":~A,\"worst_zone\":\"~A\",\"headroom_pct\":~D}"
            assessments-json
            (cpr-worst-zone plan)
            (cpr-headroom-pct plan))))
