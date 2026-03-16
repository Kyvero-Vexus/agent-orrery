;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; session-analytics.lisp — Coalton pure session duration and token-efficiency metrics
;;;
;;; All functions pure and total.
;;; Bead: agent-orrery-3jv

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Session Metric ───

  (define-type SessionMetric
    "Typed metric for one session."
    (SessionMetric String    ; session-id
                   Integer   ; duration-seconds
                   Integer   ; total-tokens
                   Integer   ; message-count
                   Integer   ; estimated-cost-cents
                   String))  ; model

  (declare sm-id (SessionMetric -> String))
  (define (sm-id m) (match m ((SessionMetric id _ _ _ _ _) id)))

  (declare sm-duration (SessionMetric -> Integer))
  (define (sm-duration m) (match m ((SessionMetric _ d _ _ _ _) d)))

  (declare sm-tokens (SessionMetric -> Integer))
  (define (sm-tokens m) (match m ((SessionMetric _ _ t _ _ _) t)))

  (declare sm-messages (SessionMetric -> Integer))
  (define (sm-messages m) (match m ((SessionMetric _ _ _ mc _ _) mc)))

  (declare sm-cost (SessionMetric -> Integer))
  (define (sm-cost m) (match m ((SessionMetric _ _ _ _ c _) c)))

  (declare sm-model (SessionMetric -> String))
  (define (sm-model m) (match m ((SessionMetric _ _ _ _ _ model) model)))

  ;; ─── Efficiency Metrics ───

  (define-type EfficiencyMetrics
    "Token efficiency ratios for a session."
    (EfficiencyMetrics String    ; session-id
                       Integer   ; tokens-per-message
                       Integer   ; tokens-per-minute
                       Integer   ; cost-per-1k-tokens (millicents)
                       Integer)) ; messages-per-minute (x100 for precision)

  (declare em-id (EfficiencyMetrics -> String))
  (define (em-id e) (match e ((EfficiencyMetrics id _ _ _ _) id)))

  (declare em-tokens-per-message (EfficiencyMetrics -> Integer))
  (define (em-tokens-per-message e) (match e ((EfficiencyMetrics _ t _ _ _) t)))

  (declare em-tokens-per-minute (EfficiencyMetrics -> Integer))
  (define (em-tokens-per-minute e) (match e ((EfficiencyMetrics _ _ t _ _) t)))

  (declare em-cost-per-1k (EfficiencyMetrics -> Integer))
  (define (em-cost-per-1k e) (match e ((EfficiencyMetrics _ _ _ c _) c)))

  (declare em-messages-per-min-x100 (EfficiencyMetrics -> Integer))
  (define (em-messages-per-min-x100 e) (match e ((EfficiencyMetrics _ _ _ _ m) m)))

  ;; ─── Duration Distribution ───

  (define-type DurationBucket
    "A histogram bucket for session durations."
    (DurationBucket String    ; label (e.g., "<1min", "1-5min")
                    Integer   ; lower-bound-seconds
                    Integer   ; upper-bound-seconds
                    Integer)) ; count

  (declare db-label (DurationBucket -> String))
  (define (db-label b) (match b ((DurationBucket l _ _ _) l)))

  (declare db-lower (DurationBucket -> Integer))
  (define (db-lower b) (match b ((DurationBucket _ lo _ _) lo)))

  (declare db-upper (DurationBucket -> Integer))
  (define (db-upper b) (match b ((DurationBucket _ _ hi _) hi)))

  (declare db-count (DurationBucket -> Integer))
  (define (db-count b) (match b ((DurationBucket _ _ _ c) c)))

  ;; ─── Aggregate Analytics ───

  (define-type SessionAnalyticsSummary
    "Aggregate session analytics."
    (SessionAnalyticsSummary Integer                ; total-sessions
                             Integer                ; avg-duration-seconds
                             Integer                ; median-tokens
                             Integer                ; avg-tokens-per-message
                             Integer                ; total-cost-cents
                             (List DurationBucket)  ; duration distribution
                             (List EfficiencyMetrics))) ; per-session efficiency

  (declare sas-total (SessionAnalyticsSummary -> Integer))
  (define (sas-total s) (match s ((SessionAnalyticsSummary t _ _ _ _ _ _) t)))

  (declare sas-avg-duration (SessionAnalyticsSummary -> Integer))
  (define (sas-avg-duration s) (match s ((SessionAnalyticsSummary _ d _ _ _ _ _) d)))

  (declare sas-median-tokens (SessionAnalyticsSummary -> Integer))
  (define (sas-median-tokens s) (match s ((SessionAnalyticsSummary _ _ m _ _ _ _) m)))

  (declare sas-avg-tokens-per-msg (SessionAnalyticsSummary -> Integer))
  (define (sas-avg-tokens-per-msg s) (match s ((SessionAnalyticsSummary _ _ _ t _ _ _) t)))

  (declare sas-total-cost (SessionAnalyticsSummary -> Integer))
  (define (sas-total-cost s) (match s ((SessionAnalyticsSummary _ _ _ _ c _ _) c)))

  (declare sas-duration-buckets (SessionAnalyticsSummary -> (List DurationBucket)))
  (define (sas-duration-buckets s) (match s ((SessionAnalyticsSummary _ _ _ _ _ b _) b)))

  (declare sas-efficiency (SessionAnalyticsSummary -> (List EfficiencyMetrics)))
  (define (sas-efficiency s) (match s ((SessionAnalyticsSummary _ _ _ _ _ _ e) e)))

  ;; ─── Core Logic ───

  (declare %sa-safe-div (Integer -> Integer -> Integer))
  (define (%sa-safe-div num denom)
    (if (== denom 0) 0 (lisp Integer (num denom) (cl:values (cl:truncate num denom)))))

  (declare compute-efficiency (SessionMetric -> EfficiencyMetrics))
  (define (compute-efficiency m)
    (let ((duration-min (%sa-safe-div (sm-duration m) 60)))
      (EfficiencyMetrics
       (sm-id m)
       (%sa-safe-div (sm-tokens m) (sm-messages m))
       (%sa-safe-div (sm-tokens m) (max 1 duration-min))
       (%sa-safe-div (* (sm-cost m) 1000) (max 1 (sm-tokens m)))
       (%sa-safe-div (* (sm-messages m) 100) (max 1 duration-min)))))

  (declare %count-in-range (Integer -> Integer -> (List SessionMetric) -> Integer))
  (define (%count-in-range lo hi metrics)
    (fold (fn (acc m)
            (if (and (>= (sm-duration m) lo) (< (sm-duration m) hi))
                (+ acc 1)
                acc))
          0
          metrics))

  (declare build-duration-distribution ((List SessionMetric) -> (List DurationBucket)))
  (define (build-duration-distribution metrics)
    (Cons (DurationBucket "<1min" 0 60 (%count-in-range 0 60 metrics))
          (Cons (DurationBucket "1-5min" 60 300 (%count-in-range 60 300 metrics))
                (Cons (DurationBucket "5-15min" 300 900 (%count-in-range 300 900 metrics))
                      (Cons (DurationBucket "15-60min" 900 3600 (%count-in-range 900 3600 metrics))
                            (Cons (DurationBucket ">60min" 3600 999999 (%count-in-range 3600 999999 metrics))
                                  (the (List DurationBucket) Nil)))))))

  (declare %sum-field ((SessionMetric -> Integer) -> (List SessionMetric) -> Integer))
  (define (%sum-field getter metrics)
    (fold (fn (acc m) (+ acc (getter m))) 0 metrics))

  (declare %count-metrics ((List SessionMetric) -> Integer))
  (define (%count-metrics metrics)
    (fold (fn (acc _m) (+ acc 1)) 0 metrics))

  (declare analyze-sessions ((List SessionMetric) -> SessionAnalyticsSummary))
  (define (analyze-sessions metrics)
    "Compute aggregate session analytics from a list of session metrics."
    (let ((count (%count-metrics metrics))
          (total-duration (%sum-field sm-duration metrics))
          (total-tokens (%sum-field sm-tokens metrics))
          (total-messages (%sum-field sm-messages metrics))
          (total-cost (%sum-field sm-cost metrics)))
      (SessionAnalyticsSummary
       count
       (%sa-safe-div total-duration count)
       (%sa-safe-div total-tokens count)
       (%sa-safe-div total-tokens (max 1 total-messages))
       total-cost
       (build-duration-distribution metrics)
       (map compute-efficiency metrics)))))

;;; ─── CL Bridge ───

(cl:defun cl-make-session-metric (id duration tokens messages cost model)
  (coalton:coalton
   (SessionMetric (lisp String () id)
                  (lisp Integer () duration)
                  (lisp Integer () tokens)
                  (lisp Integer () messages)
                  (lisp Integer () cost)
                  (lisp String () model))))

(cl:defun cl-compute-efficiency (m)
  (coalton:coalton (compute-efficiency (lisp SessionMetric () m))))

(cl:defun cl-analyze-sessions (metrics)
  (coalton:coalton (analyze-sessions (lisp (List SessionMetric) () metrics))))

(cl:defun cl-em-id (e) (coalton:coalton (em-id (lisp EfficiencyMetrics () e))))
(cl:defun cl-em-tokens-per-message (e) (coalton:coalton (em-tokens-per-message (lisp EfficiencyMetrics () e))))
(cl:defun cl-em-tokens-per-minute (e) (coalton:coalton (em-tokens-per-minute (lisp EfficiencyMetrics () e))))
(cl:defun cl-em-cost-per-1k (e) (coalton:coalton (em-cost-per-1k (lisp EfficiencyMetrics () e))))

(cl:defun cl-sas-total (s) (coalton:coalton (sas-total (lisp SessionAnalyticsSummary () s))))
(cl:defun cl-sas-avg-duration (s) (coalton:coalton (sas-avg-duration (lisp SessionAnalyticsSummary () s))))
(cl:defun cl-sas-median-tokens (s) (coalton:coalton (sas-median-tokens (lisp SessionAnalyticsSummary () s))))
(cl:defun cl-sas-avg-tokens-per-msg (s) (coalton:coalton (sas-avg-tokens-per-msg (lisp SessionAnalyticsSummary () s))))
(cl:defun cl-sas-total-cost (s) (coalton:coalton (sas-total-cost (lisp SessionAnalyticsSummary () s))))
(cl:defun cl-sas-duration-buckets (s) (coalton:coalton (sas-duration-buckets (lisp SessionAnalyticsSummary () s))))
(cl:defun cl-sas-efficiency (s) (coalton:coalton (sas-efficiency (lisp SessionAnalyticsSummary () s))))

(cl:defun cl-db-label (b) (coalton:coalton (db-label (lisp DurationBucket () b))))
(cl:defun cl-db-count (b) (coalton:coalton (db-count (lisp DurationBucket () b))))
