;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; v2-projection-bridge.lisp — Typed projection bridge for audit-trail + session-analytics
;;;
;;; Maps Coalton outputs into interface-neutral domain records
;;; consumed by Web/TUI/McCLIM adapters. Deterministic ordering.
;;;
;;; Bead: agent-orrery-4zp

(in-package #:orrery/adapter)

;;; ─── Audit Trail Projection ───

(defstruct (audit-entry-projection (:conc-name aep-))
  "Interface-neutral audit entry for UI consumption."
  (seq 0 :type integer)
  (timestamp 0 :type integer)
  (category "" :type string)
  (severity "" :type string)
  (actor "" :type string)
  (summary "" :type string)
  (detail "" :type string)
  (hash "" :type string))

(declaim (ftype (function (t) (values audit-entry-projection &optional))
                coalton-audit-entry->projection))
(defun coalton-audit-entry->projection (coalton-entry)
  "Convert a Coalton AuditEntry into an interface-neutral projection."
  (declare (optimize (safety 3)))
  (make-audit-entry-projection
   :seq (orrery/coalton/core:cl-entry-seq coalton-entry)
   :timestamp (orrery/coalton/core:cl-entry-timestamp coalton-entry)
   :category (orrery/coalton/core:cl-entry-category-label coalton-entry)
   :severity (orrery/coalton/core:cl-entry-severity-label coalton-entry)
   :actor (orrery/coalton/core:cl-entry-actor coalton-entry)
   :summary (orrery/coalton/core:cl-entry-summary coalton-entry)
   :detail (orrery/coalton/core:cl-entry-detail coalton-entry)
   :hash (orrery/coalton/core:cl-entry-hash coalton-entry)))

(declaim (ftype (function (audit-entry-projection) (values string &optional))
                audit-entry-projection->json))
(defun audit-entry-projection->json (proj)
  (declare (type audit-entry-projection proj) (optimize (safety 3)))
  (format nil "{\"seq\":~D,\"ts\":~D,\"category\":\"~A\",\"severity\":\"~A\",\"actor\":\"~A\",\"summary\":\"~A\"}"
          (aep-seq proj) (aep-timestamp proj) (aep-category proj)
          (aep-severity proj) (aep-actor proj) (aep-summary proj)))

;;; ─── Session Analytics Projection ───

(defstruct (session-analytics-projection (:conc-name sap-))
  "Interface-neutral session analytics summary for UI consumption."
  (total-sessions 0 :type integer)
  (avg-duration-seconds 0 :type integer)
  (avg-tokens-per-msg 0 :type integer)
  (median-tokens 0 :type integer)
  (total-cost-cents 0 :type integer)
  (duration-buckets nil :type list)
  (efficiency-summaries nil :type list))

(defstruct (duration-bucket-projection (:conc-name dbp-))
  "Interface-neutral duration bucket."
  (label "" :type string)
  (count 0 :type integer))

(defstruct (efficiency-projection (:conc-name efp-))
  "Interface-neutral efficiency metrics for one session."
  (session-id "" :type string)
  (tokens-per-message 0 :type integer)
  (tokens-per-minute 0 :type integer)
  (cost-per-1k 0 :type integer))

(declaim (ftype (function (t) (values session-analytics-projection &optional))
                coalton-analytics->projection))
(defun coalton-analytics->projection (coalton-summary)
  "Convert Coalton SessionAnalyticsSummary into interface-neutral projection."
  (declare (optimize (safety 3)))
  (let ((buckets (mapcar (lambda (b)
                           (make-duration-bucket-projection
                            :label (orrery/coalton/core:cl-db-label b)
                            :count (orrery/coalton/core:cl-db-count b)))
                         (orrery/coalton/core:cl-sas-duration-buckets coalton-summary)))
        (effs (mapcar (lambda (e)
                        (make-efficiency-projection
                         :session-id (orrery/coalton/core:cl-em-id e)
                         :tokens-per-message (orrery/coalton/core:cl-em-tokens-per-message e)
                         :tokens-per-minute (orrery/coalton/core:cl-em-tokens-per-minute e)
                         :cost-per-1k (orrery/coalton/core:cl-em-cost-per-1k e)))
                      (orrery/coalton/core:cl-sas-efficiency coalton-summary))))
    (make-session-analytics-projection
     :total-sessions (orrery/coalton/core:cl-sas-total coalton-summary)
     :avg-duration-seconds (orrery/coalton/core:cl-sas-avg-duration coalton-summary)
     :avg-tokens-per-msg (orrery/coalton/core:cl-sas-avg-tokens-per-msg coalton-summary)
     :median-tokens (orrery/coalton/core:cl-sas-median-tokens coalton-summary)
     :total-cost-cents (orrery/coalton/core:cl-sas-total-cost coalton-summary)
     :duration-buckets buckets
     :efficiency-summaries effs)))

(declaim (ftype (function (session-analytics-projection) (values string &optional))
                session-analytics-projection->json))
(defun session-analytics-projection->json (proj)
  (declare (type session-analytics-projection proj) (optimize (safety 3)))
  (format nil "{\"total\":~D,\"avg_duration_s\":~D,\"avg_tokens_per_msg\":~D,\"total_cost_cents\":~D,\"buckets\":[~{~A~^,~}]}"
          (sap-total-sessions proj)
          (sap-avg-duration-seconds proj)
          (sap-avg-tokens-per-msg proj)
          (sap-total-cost-cents proj)
          (mapcar (lambda (b)
                    (format nil "{\"label\":\"~A\",\"count\":~D}"
                            (dbp-label b) (dbp-count b)))
                  (sap-duration-buckets proj))))

;;; ─── Pagination Contract ───

(defstruct (page-request (:conc-name pr-))
  "Deterministic pagination request."
  (offset 0 :type fixnum)
  (limit 50 :type fixnum)
  (sort-key :timestamp :type keyword)
  (sort-order :desc :type (member :asc :desc)))

(defstruct (page-response (:conc-name pres-))
  "Typed page response wrapper."
  (items nil :type list)
  (total 0 :type fixnum)
  (offset 0 :type fixnum)
  (limit 0 :type fixnum)
  (has-more-p nil :type boolean))

(declaim (ftype (function (list page-request) (values page-response &optional))
                paginate-items))
(defun paginate-items (items request)
  "Apply deterministic pagination to ITEMS. Pure."
  (declare (type list items) (type page-request request) (optimize (safety 3)))
  (let* ((total (length items))
         (offset (min (pr-offset request) total))
         (limit (pr-limit request))
         (end (min (+ offset limit) total))
         (page (subseq items offset end)))
    (make-page-response
     :items page
     :total total
     :offset offset
     :limit limit
     :has-more-p (< end total))))
