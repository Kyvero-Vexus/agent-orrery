;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; session-analytics-bridge.lisp — CL adapter for Coalton session analytics
;;;
;;; Bead: agent-orrery-swhu

(in-package #:orrery/adapter)

;;; The domain types (analytics-summary, duration-bucket-record, efficiency-record)
;;; are already defined in src/domain/types.lisp, so we just provide conversion functions.

(declaim
 (ftype (function (t) (values analytics-summary list list &optional)) coalton-analytics->cl)
 (ftype (function (t) (values duration-bucket-record &optional)) coalton-bucket->cl)
 (ftype (function (t) (values efficiency-record &optional)) coalton-efficiency->cl)
 (ftype (function (analytics-summary) (values string &optional)) analytics-summary->json)
 (ftype (function (duration-bucket-record) (values string &optional)) duration-bucket->json)
 (ftype (function (efficiency-record) (values string &optional)) efficiency-record->json))

(defun coalton-bucket->cl (coalton-bucket)
  "Convert a Coalton DurationBucket to CL duration-bucket-record."
  (declare (optimize (safety 3)))
  (make-duration-bucket-record
   :label (orrery/coalton/core:cl-db-label coalton-bucket)
   :count (orrery/coalton/core:cl-db-count coalton-bucket)))

(defun coalton-efficiency->cl (coalton-eff)
  "Convert a Coalton EfficiencyMetrics to CL efficiency-record."
  (declare (optimize (safety 3)))
  (make-efficiency-record
   :session-id (orrery/coalton/core:cl-em-id coalton-eff)
   :tokens-per-message (orrery/coalton/core:cl-em-tokens-per-message coalton-eff)
   :tokens-per-minute (orrery/coalton/core:cl-em-tokens-per-minute coalton-eff)
   :cost-per-1k (orrery/coalton/core:cl-em-cost-per-1k coalton-eff)))

(defun coalton-analytics->cl (coalton-summary)
  "Convert a Coalton SessionAnalyticsSummary to CL analytics-summary."
  (declare (optimize (safety 3)))
  (let* ((buckets (orrery/coalton/core:cl-sas-duration-buckets coalton-summary))
         (effs (orrery/coalton/core:cl-sas-efficiency coalton-summary)))
    (values
     (make-analytics-summary
      :total-sessions (orrery/coalton/core:cl-sas-total coalton-summary)
      :avg-duration-s (orrery/coalton/core:cl-sas-avg-duration coalton-summary)
      :median-tokens (orrery/coalton/core:cl-sas-median-tokens coalton-summary)
      :avg-tokens-per-msg (orrery/coalton/core:cl-sas-avg-tokens-per-msg coalton-summary)
      :total-cost-cents (orrery/coalton/core:cl-sas-total-cost coalton-summary))
     (mapcar #'coalton-bucket->cl buckets)
     (mapcar #'coalton-efficiency->cl effs))))

(defun duration-bucket->json (bucket)
  "Deterministic JSON emitter for duration bucket."
  (declare (type duration-bucket-record bucket) (optimize (safety 3)))
  (format nil "{\"label\":\"~A\",\"count\":~D}"
          (dbr-label bucket)
          (dbr-count bucket)))

(defun efficiency-record->json (eff)
  "Deterministic JSON emitter for efficiency record."
  (declare (type efficiency-record eff) (optimize (safety 3)))
  (format nil "{\"session_id\":\"~A\",\"tokens_per_message\":~D,\"tokens_per_minute\":~D,\"cost_per_1k\":~D}"
          (efr-session-id eff)
          (efr-tokens-per-message eff)
          (efr-tokens-per-minute eff)
          (efr-cost-per-1k eff)))

(defun analytics-summary->json (summary &optional buckets efficiencies)
  "Deterministic JSON emitter for analytics summary with optional bucket/efficiency lists."
  (declare (type analytics-summary summary) (optimize (safety 3)))
  (let ((buckets-json (format nil "[~{~A~^,~}]"
                               (mapcar #'duration-bucket->json (or buckets nil))))
        (effs-json (format nil "[~{~A~^,~}]"
                            (mapcar #'efficiency-record->json (or efficiencies nil)))))
    (format nil "{\"total_sessions\":~D,\"avg_duration_s\":~D,\"median_tokens\":~D,\"avg_tokens_per_msg\":~D,\"total_cost_cents\":~D,\"duration_buckets\":~A,\"efficiency_metrics\":~A}"
            (asm-total-sessions summary)
            (asm-avg-duration-s summary)
            (asm-median-tokens summary)
            (asm-avg-tokens-per-msg summary)
            (asm-total-cost-cents summary)
            buckets-json
            effs-json)))
