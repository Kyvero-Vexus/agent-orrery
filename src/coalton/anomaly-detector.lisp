;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; anomaly-detector.lisp — Coalton pure-core anomaly detection pipeline
;;;
;;; Typed, side-effect-free anomaly scoring for session/cost drift,
;;; runaway token usage, and model-routing regressions across adapters.
;;; All functions are pure; no I/O or mutable state.

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Anomaly Severity ───

  (define-type AnomalySeverity
    AnomalyNone
    AnomalyWarning
    AnomalyCritical)

  (define-instance (Eq AnomalySeverity)
    (define (== a b)
      (match a
        ((AnomalyNone) (match b ((AnomalyNone) True) (_ False)))
        ((AnomalyWarning) (match b ((AnomalyWarning) True) (_ False)))
        ((AnomalyCritical) (match b ((AnomalyCritical) True) (_ False))))))

  (declare severity-rank (AnomalySeverity -> Integer))
  (define (severity-rank s)
    (match s
      ((AnomalyNone) 0)
      ((AnomalyWarning) 1)
      ((AnomalyCritical) 2)))

  (declare max-severity (AnomalySeverity -> AnomalySeverity -> AnomalySeverity))
  (define (max-severity a b)
    (if (>= (severity-rank a) (severity-rank b)) a b))

  ;; ─── Anomaly Kind ───

  (define-type AnomalyKind
    SessionCountDrift     ; sudden change in active session count
    CostRunaway           ; cost exceeds threshold relative to baseline
    TokenSpikeDetected    ; token usage spike in a single period
    ModelRoutingShift     ; model distribution changed significantly
    AdapterDivergence)    ; two adapters disagree on session/cost data

  (define-instance (Eq AnomalyKind)
    (define (== a b)
      (match a
        ((SessionCountDrift) (match b ((SessionCountDrift) True) (_ False)))
        ((CostRunaway) (match b ((CostRunaway) True) (_ False)))
        ((TokenSpikeDetected) (match b ((TokenSpikeDetected) True) (_ False)))
        ((ModelRoutingShift) (match b ((ModelRoutingShift) True) (_ False)))
        ((AdapterDivergence) (match b ((AdapterDivergence) True) (_ False))))))

  ;; ─── Anomaly Finding ───

  (define-type AnomalyFinding
    (AnomalyFinding AnomalyKind      ; what kind
                    AnomalySeverity   ; how bad
                    String            ; description
                    Integer           ; observed value
                    Integer           ; baseline/expected value
                    Integer))         ; score (0-1000, permille deviation)

  (declare af-kind (AnomalyFinding -> AnomalyKind))
  (define (af-kind f)
    (match f ((AnomalyFinding k _ _ _ _ _) k)))

  (declare af-severity (AnomalyFinding -> AnomalySeverity))
  (define (af-severity f)
    (match f ((AnomalyFinding _ s _ _ _ _) s)))

  (declare af-description (AnomalyFinding -> String))
  (define (af-description f)
    (match f ((AnomalyFinding _ _ d _ _ _) d)))

  (declare af-observed (AnomalyFinding -> Integer))
  (define (af-observed f)
    (match f ((AnomalyFinding _ _ _ o _ _) o)))

  (declare af-baseline (AnomalyFinding -> Integer))
  (define (af-baseline f)
    (match f ((AnomalyFinding _ _ _ _ b _) b)))

  (declare af-score (AnomalyFinding -> Integer))
  (define (af-score f)
    (match f ((AnomalyFinding _ _ _ _ _ s) s)))

  ;; ─── Anomaly Report ───

  (define-type AnomalyReport
    (AnomalyReport (List AnomalyFinding)  ; findings
                   AnomalySeverity         ; worst severity
                   Integer                 ; total anomaly count
                   Integer))               ; aggregate risk score (0-1000)

  (declare ar-findings (AnomalyReport -> (List AnomalyFinding)))
  (define (ar-findings r)
    (match r ((AnomalyReport fs _ _ _) fs)))

  (declare ar-worst-severity (AnomalyReport -> AnomalySeverity))
  (define (ar-worst-severity r)
    (match r ((AnomalyReport _ s _ _) s)))

  (declare ar-anomaly-count (AnomalyReport -> Integer))
  (define (ar-anomaly-count r)
    (match r ((AnomalyReport _ _ c _) c)))

  (declare ar-risk-score (AnomalyReport -> Integer))
  (define (ar-risk-score r)
    (match r ((AnomalyReport _ _ _ s) s)))

  ;; ─── Thresholds ───

  (define-type AnomalyThresholds
    (AnomalyThresholds Integer   ; session-drift-warning-pct (permille)
                       Integer   ; session-drift-critical-pct (permille)
                       Integer   ; cost-runaway-warning-pct (permille)
                       Integer   ; cost-runaway-critical-pct (permille)
                       Integer   ; token-spike-warning-pct (permille)
                       Integer   ; token-spike-critical-pct (permille)
                       Integer   ; model-shift-warning-pct (permille)
                       Integer)) ; model-shift-critical-pct (permille)

  (declare at-session-warn (AnomalyThresholds -> Integer))
  (define (at-session-warn t)
    (match t ((AnomalyThresholds w _ _ _ _ _ _ _) w)))

  (declare at-session-crit (AnomalyThresholds -> Integer))
  (define (at-session-crit t)
    (match t ((AnomalyThresholds _ c _ _ _ _ _ _) c)))

  (declare at-cost-warn (AnomalyThresholds -> Integer))
  (define (at-cost-warn t)
    (match t ((AnomalyThresholds _ _ w _ _ _ _ _) w)))

  (declare at-cost-crit (AnomalyThresholds -> Integer))
  (define (at-cost-crit t)
    (match t ((AnomalyThresholds _ _ _ c _ _ _ _) c)))

  (declare at-token-warn (AnomalyThresholds -> Integer))
  (define (at-token-warn t)
    (match t ((AnomalyThresholds _ _ _ _ w _ _ _) w)))

  (declare at-token-crit (AnomalyThresholds -> Integer))
  (define (at-token-crit t)
    (match t ((AnomalyThresholds _ _ _ _ _ c _ _) c)))

  (declare at-model-warn (AnomalyThresholds -> Integer))
  (define (at-model-warn t)
    (match t ((AnomalyThresholds _ _ _ _ _ _ w _) w)))

  (declare at-model-crit (AnomalyThresholds -> Integer))
  (define (at-model-crit t)
    (match t ((AnomalyThresholds _ _ _ _ _ _ _ c) c)))

  ;; ─── Default Thresholds ───

  (declare default-thresholds (Unit -> AnomalyThresholds))
  (define (default-thresholds)
    (AnomalyThresholds
     200   ; session drift warn at 20%
     500   ; session drift crit at 50%
     300   ; cost runaway warn at 30%
     700   ; cost runaway crit at 70%
     400   ; token spike warn at 40%
     800   ; token spike crit at 80%
     150   ; model shift warn at 15%
     400)) ; model shift crit at 40%

  ;; ─── Integer Abs ───

  (declare %abs (Integer -> Integer))
  (define (%abs x)
    (if (< x 0) (negate x) x))

  ;; ─── Integer Division Helper ───

  (declare %idiv (Integer -> Integer -> Integer))
  (define (%idiv a b)
    (lisp Integer (a b) (cl:values (cl:truncate a b))))

  ;; ─── Deviation Permille (safe division) ───

  (declare deviation-permille (Integer -> Integer -> Integer))
  (define (deviation-permille observed baseline)
    "Compute |observed - baseline| / baseline * 1000 as integer permille.
     Returns 0 if baseline is 0 and observed is 0, 1000 if baseline is 0."
    (if (== baseline 0)
        (if (== observed 0) 0 1000)
        (%idiv (* (%abs (- observed baseline)) 1000) (%abs baseline))))

  ;; ─── Classify Deviation ───

  (declare classify-deviation (Integer -> Integer -> Integer -> AnomalySeverity))
  (define (classify-deviation permille warn-threshold crit-threshold)
    (if (>= permille crit-threshold)
        AnomalyCritical
        (if (>= permille warn-threshold)
            AnomalyWarning
            AnomalyNone)))

  ;; ─── Session Count Drift Detector ───

  (declare detect-session-drift (AnomalyThresholds -> Integer -> Integer -> (List AnomalyFinding)))
  (define (detect-session-drift thresholds current-count baseline-count)
    "Detect anomalous session count changes."
    (let ((dev (deviation-permille current-count baseline-count))
          (sev (classify-deviation
                (deviation-permille current-count baseline-count)
                (at-session-warn thresholds)
                (at-session-crit thresholds))))
      (match sev
        ((AnomalyNone) Nil)
        (_ (Cons (AnomalyFinding SessionCountDrift sev
                                 "Session count drift detected"
                                 current-count baseline-count dev)
                 Nil)))))

  ;; ─── Cost Runaway Detector ───

  (declare detect-cost-runaway (AnomalyThresholds -> Integer -> Integer -> (List AnomalyFinding)))
  (define (detect-cost-runaway thresholds current-cost baseline-cost)
    "Detect runaway cost relative to baseline."
    (let ((dev (deviation-permille current-cost baseline-cost))
          (sev (classify-deviation
                (deviation-permille current-cost baseline-cost)
                (at-cost-warn thresholds)
                (at-cost-crit thresholds))))
      (match sev
        ((AnomalyNone) Nil)
        (_ (Cons (AnomalyFinding CostRunaway sev
                                 "Cost runaway detected"
                                 current-cost baseline-cost dev)
                 Nil)))))

  ;; ─── Token Spike Detector ───

  (declare detect-token-spike (AnomalyThresholds -> Integer -> Integer -> (List AnomalyFinding)))
  (define (detect-token-spike thresholds current-tokens baseline-tokens)
    "Detect abnormal token usage spike."
    (let ((dev (deviation-permille current-tokens baseline-tokens))
          (sev (classify-deviation
                (deviation-permille current-tokens baseline-tokens)
                (at-token-warn thresholds)
                (at-token-crit thresholds))))
      (match sev
        ((AnomalyNone) Nil)
        (_ (Cons (AnomalyFinding TokenSpikeDetected sev
                                 "Token spike detected"
                                 current-tokens baseline-tokens dev)
                 Nil)))))

  ;; ─── Model Routing Shift Detector ───
  ;; Takes two lists of ModelRank (baseline and current), computes
  ;; max permille shift across all models present in either.

  (declare %lookup-model-permille (String -> (List ModelRank) -> Integer))
  (define (%lookup-model-permille model ranks)
    (match ranks
      ((Nil) 0)
      ((Cons r rest)
       (if (== (mr-model r) model)
           (mr-permille r)
           (%lookup-model-permille model rest)))))

  (declare %model-names ((List ModelRank) -> (List String)))
  (define (%model-names ranks)
    (map mr-model ranks))

  (declare %contains-string (String -> (List String) -> Boolean))
  (define (%contains-string needle xs)
    (match xs
      ((Nil) False)
      ((Cons x rest)
       (if (== x needle) True (%contains-string needle rest)))))

  (declare %unique-strings ((List String) -> (List String)))
  (define (%unique-strings xs)
    (match xs
      ((Nil) Nil)
      ((Cons x rest)
       (if (%contains-string x rest)
           (%unique-strings rest)
           (Cons x (%unique-strings rest))))))

  (declare %max-model-shift ((List ModelRank) -> (List ModelRank) -> Integer))
  (define (%max-model-shift baseline current)
    (let ((all-models (%unique-strings
                       (append (%model-names baseline) (%model-names current)))))
      (fold (fn (mx model)
              (let ((b-pml (%lookup-model-permille model baseline))
                    (c-pml (%lookup-model-permille model current)))
                (max mx (%abs (- c-pml b-pml)))))
            0 all-models)))

  (declare detect-model-shift (AnomalyThresholds -> (List ModelRank) -> (List ModelRank)
                               -> (List AnomalyFinding)))
  (define (detect-model-shift thresholds baseline-ranks current-ranks)
    "Detect significant model distribution shift."
    (let ((shift (%max-model-shift baseline-ranks current-ranks))
          (sev (classify-deviation shift
                                   (at-model-warn thresholds)
                                   (at-model-crit thresholds))))
      (match sev
        ((AnomalyNone) Nil)
        (_ (Cons (AnomalyFinding ModelRoutingShift sev
                                 "Model routing distribution shift detected"
                                 shift 0 shift)
                 Nil)))))

  ;; ─── Adapter Divergence Detector ───
  ;; Compares token totals from two adapters for the same period.

  (declare detect-adapter-divergence (AnomalyThresholds -> Integer -> Integer
                                     -> (List AnomalyFinding)))
  (define (detect-adapter-divergence thresholds adapter-a-tokens adapter-b-tokens)
    "Detect divergence between two adapters' token counts."
    (let ((dev (deviation-permille adapter-a-tokens adapter-b-tokens))
          (sev (classify-deviation dev
                                   (at-session-warn thresholds)
                                   (at-session-crit thresholds))))
      (match sev
        ((AnomalyNone) Nil)
        (_ (Cons (AnomalyFinding AdapterDivergence sev
                                 "Adapter token count divergence detected"
                                 adapter-a-tokens adapter-b-tokens dev)
                 Nil)))))

  ;; ─── Aggregate Risk Score ───

  (declare %clamp (Integer -> Integer -> Integer -> Integer))
  (define (%clamp lo hi x)
    (if (< x lo) lo (if (> x hi) hi x)))

  (declare %count-findings ((List AnomalyFinding) -> Integer))
  (define (%count-findings findings)
    (fold (fn (acc _) (+ acc 1)) 0 findings))

  (declare compute-risk-score ((List AnomalyFinding) -> Integer))
  (define (compute-risk-score findings)
    "Aggregate risk from 0-1000 based on finding scores and severities."
    (let ((raw (fold (fn (acc f)
                       (+ acc (* (af-score f) (severity-rank (af-severity f)))))
                     0 findings))
          (count (%count-findings findings)))
      (%clamp 0 1000
              (if (== count 0)
                  0
                  (%idiv raw count)))))

  ;; ─── Build Anomaly Report ───

  (declare build-anomaly-report ((List AnomalyFinding) -> AnomalyReport))
  (define (build-anomaly-report findings)
    (let ((worst (fold (fn (acc f) (max-severity acc (af-severity f)))
                       AnomalyNone findings))
          (count (%count-findings findings))
          (risk (compute-risk-score findings)))
      (AnomalyReport findings worst count risk)))

  ;; ─── Full Pipeline ───

  (declare run-anomaly-pipeline
           (AnomalyThresholds
            -> Integer -> Integer   ; session counts (current, baseline)
            -> Integer -> Integer   ; costs (current, baseline)
            -> Integer -> Integer   ; tokens (current, baseline)
            -> (List ModelRank) -> (List ModelRank)  ; model ranks
            -> AnomalyReport))
  (define (run-anomaly-pipeline thresholds
                                session-cur session-base
                                cost-cur cost-base
                                token-cur token-base
                                model-cur model-base)
    (build-anomaly-report
     (append (detect-session-drift thresholds session-cur session-base)
             (append (detect-cost-runaway thresholds cost-cur cost-base)
                     (append (detect-token-spike thresholds token-cur token-base)
                             (detect-model-shift thresholds model-base model-cur)))))))

;;; ─── CL-callable bridge ───

(cl:defun cl-default-thresholds ()
  "CL-callable: return default anomaly thresholds."
  (coalton:coalton (default-thresholds)))

(cl:defun cl-deviation-permille (observed baseline)
  "CL-callable: compute deviation permille."
  (coalton:coalton
   (deviation-permille
    (lisp Integer () observed)
    (lisp Integer () baseline))))

(cl:defun cl-detect-session-drift (thresholds current baseline)
  "CL-callable: detect session count drift."
  (coalton:coalton
   (detect-session-drift
    (lisp AnomalyThresholds () thresholds)
    (lisp Integer () current)
    (lisp Integer () baseline))))

(cl:defun cl-detect-cost-runaway (thresholds current baseline)
  "CL-callable: detect cost runaway."
  (coalton:coalton
   (detect-cost-runaway
    (lisp AnomalyThresholds () thresholds)
    (lisp Integer () current)
    (lisp Integer () baseline))))

(cl:defun cl-detect-token-spike (thresholds current baseline)
  "CL-callable: detect token spike."
  (coalton:coalton
   (detect-token-spike
    (lisp AnomalyThresholds () thresholds)
    (lisp Integer () current)
    (lisp Integer () baseline))))

(cl:defun cl-detect-adapter-divergence (thresholds a-tokens b-tokens)
  "CL-callable: detect adapter divergence."
  (coalton:coalton
   (detect-adapter-divergence
    (lisp AnomalyThresholds () thresholds)
    (lisp Integer () a-tokens)
    (lisp Integer () b-tokens))))

(cl:defun cl-run-anomaly-pipeline (thresholds
                                   session-cur session-base
                                   cost-cur cost-base
                                   token-cur token-base
                                   model-cur model-base)
  "CL-callable: run full anomaly detection pipeline."
  (coalton:coalton
   (run-anomaly-pipeline
    (lisp AnomalyThresholds () thresholds)
    (lisp Integer () session-cur)
    (lisp Integer () session-base)
    (lisp Integer () cost-cur)
    (lisp Integer () cost-base)
    (lisp Integer () token-cur)
    (lisp Integer () token-base)
    (lisp (List ModelRank) () model-cur)
    (lisp (List ModelRank) () model-base))))

(cl:defun cl-anomaly-report-count (report)
  "CL-callable: get anomaly count from report."
  (coalton:coalton
   (ar-anomaly-count (lisp AnomalyReport () report))))

(cl:defun cl-anomaly-report-risk-score (report)
  "CL-callable: get risk score from report."
  (coalton:coalton
   (ar-risk-score (lisp AnomalyReport () report))))

(cl:defun cl-anomaly-report-findings (report)
  "CL-callable: get findings list from report."
  (coalton:coalton
   (ar-findings (lisp AnomalyReport () report))))

(cl:defun cl-finding-list-count (findings)
  "CL-callable: count findings in Coalton list."
  (coalton:coalton
   (fold (fn (acc _) (+ acc 1))
         0
         (lisp (List AnomalyFinding) () findings))))

(cl:defun cl-anomaly-report-worst-severity-label (report)
  "CL-callable: get worst anomaly severity label as string."
  (coalton:coalton
   (match (ar-worst-severity (lisp AnomalyReport () report))
     ((AnomalyNone) "none")
     ((AnomalyWarning) "warning")
     ((AnomalyCritical) "critical"))))

(cl:defun cl-anomaly-severity-label (severity)
  "CL-callable: convert severity to string label."
  (coalton:coalton
   (match (lisp AnomalySeverity () severity)
     ((AnomalyNone) "none")
     ((AnomalyWarning) "warning")
     ((AnomalyCritical) "critical"))))

(cl:defun cl-anomaly-kind-label (kind)
  "CL-callable: convert anomaly kind to string label."
  (coalton:coalton
   (match (lisp AnomalyKind () kind)
     ((SessionCountDrift) "session-count-drift")
     ((CostRunaway) "cost-runaway")
     ((TokenSpikeDetected) "token-spike")
     ((ModelRoutingShift) "model-routing-shift")
     ((AdapterDivergence) "adapter-divergence"))))
