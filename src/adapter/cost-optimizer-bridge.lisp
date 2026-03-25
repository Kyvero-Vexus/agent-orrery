;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cost-optimizer-bridge.lisp — CL adapter for Coalton cost optimization
;;;
;;; Bead: agent-orrery-lsfx

(in-package #:orrery/adapter)

(defstruct (route-recommendation (:conc-name rrec-))
  "CL-side model routing recommendation."
  (model "" :type string)
  (reason "" :type string)
  (savings-pct 0 :type integer)
  (confidence "" :type string)
  (strategy "" :type string))

(defstruct (cost-analysis-result (:conc-name car-))
  "CL-side cost analysis result."
  (current-cost 0 :type integer)
  (optimal-cost 0 :type integer)
  (savings-pct 0 :type integer)
  (strategy "" :type string)
  (recommendations nil :type list))

(declaim
 (ftype (function (t) (values route-recommendation &optional)) coalton-recommendation->cl)
 (ftype (function (t) (values cost-analysis-result &optional)) coalton-analysis->cl)
 (ftype (function (route-recommendation) (values string &optional)) route-recommendation->json)
 (ftype (function (cost-analysis-result) (values string &optional)) cost-analysis->json))

(defun coalton-recommendation->cl (coalton-rec)
  "Convert a Coalton RouteRecommendation to CL route-recommendation struct."
  (declare (optimize (safety 3)))
  (make-route-recommendation
   :model (orrery/coalton/core:cl-rr-model coalton-rec)
   :reason (orrery/coalton/core:cl-rr-reason coalton-rec)
   :savings-pct (orrery/coalton/core:cl-rr-savings-pct coalton-rec)
   :confidence (orrery/coalton/core:cl-rr-confidence-label coalton-rec)
   :strategy (orrery/coalton/core:cl-rr-strategy-label coalton-rec)))

(defun coalton-analysis->cl (coalton-analysis)
  "Convert a Coalton CostAnalysis to CL cost-analysis-result struct."
  (declare (optimize (safety 3)))
  (let ((recommendations (orrery/coalton/core:cl-ca-recommendations coalton-analysis)))
    (make-cost-analysis-result
     :current-cost (orrery/coalton/core:cl-ca-current-cost coalton-analysis)
     :optimal-cost (orrery/coalton/core:cl-ca-optimal-cost coalton-analysis)
     :savings-pct (orrery/coalton/core:cl-ca-savings-pct coalton-analysis)
     :strategy (orrery/coalton/core:cl-ca-strategy-label coalton-analysis)
     :recommendations (mapcar #'coalton-recommendation->cl recommendations))))

(defun route-recommendation->json (rec)
  "Deterministic JSON emitter for route recommendation."
  (declare (type route-recommendation rec) (optimize (safety 3)))
  (format nil "{\"model\":\"~A\",\"reason\":\"~A\",\"savings_pct\":~D,\"confidence\":\"~A\",\"strategy\":\"~A\"}"
          (rrec-model rec)
          (rrec-reason rec)
          (rrec-savings-pct rec)
          (rrec-confidence rec)
          (rrec-strategy rec)))

(defun cost-analysis->json (analysis)
  "Deterministic JSON emitter for cost analysis."
  (declare (type cost-analysis-result analysis) (optimize (safety 3)))
  (let ((recs-json (format nil "[~{~A~^,~}]"
                           (mapcar #'route-recommendation->json (car-recommendations analysis)))))
    (format nil "{\"current_cost\":~D,\"optimal_cost\":~D,\"savings_pct\":~D,\"strategy\":\"~A\",\"recommendations\":~A}"
            (car-current-cost analysis)
            (car-optimal-cost analysis)
            (car-savings-pct analysis)
            (car-strategy analysis)
            recs-json)))
