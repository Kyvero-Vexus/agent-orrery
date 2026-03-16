;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cost-optimizer.lisp — Coalton pure cost-optimization and model routing
;;;
;;; Analyzes usage patterns to recommend cost-optimal model routing.
;;; All functions pure and total. No IO.
;;;
;;; Bead: agent-orrery-nhh

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Model Cost Profile ───

  (define-type ModelCostProfile
    "Cost characteristics for a model."
    (ModelCostProfile String     ; model name
                      Integer    ; cost-per-1k-prompt-tokens (millicents)
                      Integer    ; cost-per-1k-completion-tokens (millicents)
                      Integer    ; quality-score (0-1000)
                      Integer))  ; latency-score (0-1000, lower = faster)

  (declare mcp-name (ModelCostProfile -> String))
  (define (mcp-name p)
    (match p ((ModelCostProfile n _ _ _ _) n)))

  (declare mcp-prompt-cost (ModelCostProfile -> Integer))
  (define (mcp-prompt-cost p)
    (match p ((ModelCostProfile _ c _ _ _) c)))

  (declare mcp-completion-cost (ModelCostProfile -> Integer))
  (define (mcp-completion-cost p)
    (match p ((ModelCostProfile _ _ c _ _) c)))

  (declare mcp-quality (ModelCostProfile -> Integer))
  (define (mcp-quality p)
    (match p ((ModelCostProfile _ _ _ q _) q)))

  (declare mcp-latency (ModelCostProfile -> Integer))
  (define (mcp-latency p)
    (match p ((ModelCostProfile _ _ _ _ l) l)))

  ;; ─── Optimization Strategy ───

  (repr :enum)
  (define-type OptimizationStrategy
    "What to optimize for."
    OptCost       ; minimize cost
    OptQuality    ; maximize quality
    OptBalanced   ; balance cost/quality
    OptLatency)   ; minimize latency

  ;; ─── Route Recommendation ───

  (define-type RouteConfidence
    "Confidence in a recommendation."
    ConfHigh      ; strong signal
    ConfMedium    ; moderate signal
    ConfLow)      ; weak signal / insufficient data

  (declare confidence-score (RouteConfidence -> Integer))
  (define (confidence-score c)
    (match c
      ((ConfHigh) 900)
      ((ConfMedium) 600)
      ((ConfLow) 300)))

  (declare confidence-label (RouteConfidence -> String))
  (define (confidence-label c)
    (match c
      ((ConfHigh) "high")
      ((ConfMedium) "medium")
      ((ConfLow) "low")))

  (define-type RouteRecommendation
    "A model routing recommendation."
    (RouteRecommendation String              ; recommended model
                         String              ; reason
                         Integer             ; estimated-savings-pct (vs current)
                         RouteConfidence     ; confidence
                         OptimizationStrategy)) ; strategy used

  (declare rr-model (RouteRecommendation -> String))
  (define (rr-model r)
    (match r ((RouteRecommendation m _ _ _ _) m)))

  (declare rr-reason (RouteRecommendation -> String))
  (define (rr-reason r)
    (match r ((RouteRecommendation _ reason _ _ _) reason)))

  (declare rr-savings-pct (RouteRecommendation -> Integer))
  (define (rr-savings-pct r)
    (match r ((RouteRecommendation _ _ s _ _) s)))

  (declare rr-confidence (RouteRecommendation -> RouteConfidence))
  (define (rr-confidence r)
    (match r ((RouteRecommendation _ _ _ c _) c)))

  (declare rr-strategy (RouteRecommendation -> OptimizationStrategy))
  (define (rr-strategy r)
    (match r ((RouteRecommendation _ _ _ _ s) s)))

  ;; ─── Cost Analysis Result ───

  (define-type CostAnalysis
    "Complete cost analysis with recommendations."
    (CostAnalysis Integer                     ; current-total-cost (millicents)
                  Integer                     ; optimal-total-cost (millicents)
                  Integer                     ; potential-savings-pct
                  (List RouteRecommendation)  ; recommendations
                  OptimizationStrategy))      ; strategy used

  (declare ca-current-cost (CostAnalysis -> Integer))
  (define (ca-current-cost a)
    (match a ((CostAnalysis c _ _ _ _) c)))

  (declare ca-optimal-cost (CostAnalysis -> Integer))
  (define (ca-optimal-cost a)
    (match a ((CostAnalysis _ o _ _ _) o)))

  (declare ca-savings-pct (CostAnalysis -> Integer))
  (define (ca-savings-pct a)
    (match a ((CostAnalysis _ _ s _ _) s)))

  (declare ca-recommendations (CostAnalysis -> (List RouteRecommendation)))
  (define (ca-recommendations a)
    (match a ((CostAnalysis _ _ _ rs _) rs)))

  (declare ca-strategy (CostAnalysis -> OptimizationStrategy))
  (define (ca-strategy a)
    (match a ((CostAnalysis _ _ _ _ s) s)))

  ;; ─── Core Logic ───

  (declare %safe-div-co (Integer -> Integer -> Integer))
  (define (%safe-div-co num denom)
    (if (== denom 0) 0 (lisp Integer (num denom) (cl:values (cl:truncate num denom)))))

  (declare %model-effective-cost (ModelCostProfile -> Integer -> Integer -> Integer))
  (define (%model-effective-cost profile prompt-tokens completion-tokens)
    "Compute effective cost in millicents for given token volumes."
    (+ (%safe-div-co (* (mcp-prompt-cost profile) prompt-tokens) 1000)
       (%safe-div-co (* (mcp-completion-cost profile) completion-tokens) 1000)))

  (declare %score-model (ModelCostProfile -> OptimizationStrategy -> Integer -> Integer -> Integer))
  (define (%score-model profile strategy prompt-tokens completion-tokens)
    "Score a model for routing. Higher = better."
    (let ((cost (%model-effective-cost profile prompt-tokens completion-tokens))
          (quality (mcp-quality profile))
          (latency (mcp-latency profile)))
      (match strategy
        ((OptCost)     (- 10000 cost))
        ((OptQuality)  quality)
        ((OptLatency)  (- 1000 latency))
        ((OptBalanced) (- (+ quality (%safe-div-co (* (- 1000 latency) 3) 10))
                         (%safe-div-co cost 10))))))

  (declare %find-best-model ((List ModelCostProfile) -> OptimizationStrategy -> Integer -> Integer -> ModelCostProfile))
  (define (%find-best-model profiles strategy pt ct)
    "Find the best model for the given strategy."
    (match profiles
      ((Nil) (error "No models available"))
      ((Cons first rest)
       (fold (fn (best candidate)
               (if (> (%score-model candidate strategy pt ct)
                      (%score-model best strategy pt ct))
                   candidate
                   best))
             first
             rest))))

  (declare %compute-confidence ((List UsageEntry) -> RouteConfidence))
  (define (%compute-confidence entries)
    "Confidence based on data volume."
    (let ((count (fold (fn (acc _e) (+ acc 1)) 0 entries)))
      (cond
        ((>= count 100) ConfHigh)
        ((>= count 20)  ConfMedium)
        (True           ConfLow))))

  (declare strategy-label (OptimizationStrategy -> String))
  (define (strategy-label s)
    (match s
      ((OptCost)     "cost")
      ((OptQuality)  "quality")
      ((OptBalanced) "balanced")
      ((OptLatency)  "latency")))

  ;; ─── Main Entry Points ───

  (declare recommend-model ((List ModelCostProfile) -> (List UsageEntry) -> OptimizationStrategy -> RouteRecommendation))
  (define (recommend-model profiles entries strategy)
    "Recommend the optimal model given profiles, usage history, and strategy."
    (let ((total-prompt (fold (fn (acc e) (+ acc (ue-prompt-tokens e))) 0 entries))
          (total-completion (fold (fn (acc e) (+ acc (ue-completion-tokens e))) 0 entries))
          (confidence (%compute-confidence entries)))
      (let ((best (%find-best-model profiles strategy total-prompt total-completion)))
        (RouteRecommendation
         (mcp-name best)
         (mcp-name best)
         0
         confidence
         strategy))))

  (declare analyze-cost ((List ModelCostProfile) -> (List UsageEntry) -> OptimizationStrategy -> CostAnalysis))
  (define (analyze-cost profiles entries strategy)
    "Full cost analysis: current spend vs optimal under given strategy."
    (let ((total-prompt (fold (fn (acc e) (+ acc (ue-prompt-tokens e))) 0 entries))
          (total-completion (fold (fn (acc e) (+ acc (ue-completion-tokens e))) 0 entries))
          (current-cost (fold (fn (acc e) (+ acc (ue-cost-cents e))) 0 entries)))
      (let ((best (%find-best-model profiles strategy total-prompt total-completion))
            (confidence (%compute-confidence entries)))
        (let ((optimal-cost (%model-effective-cost best total-prompt total-completion))
              (savings-pct (if (== current-cost 0) 0
                               (%safe-div-co (* (- current-cost (%model-effective-cost best total-prompt total-completion)) 100)
                                             current-cost))))
          (CostAnalysis
           current-cost
           optimal-cost
           savings-pct
           (Cons (RouteRecommendation
                  (mcp-name best)
                  (mcp-name best)
                  savings-pct
                  confidence
                  strategy)
                 (the (List RouteRecommendation) Nil))
           strategy))))))

;;; ─── CL Bridge ───

(cl:defun cl-make-model-cost-profile (name prompt-cost completion-cost quality latency)
  "CL-callable: construct a ModelCostProfile."
  (coalton:coalton
   (ModelCostProfile (lisp String () name)
                     (lisp Integer () prompt-cost)
                     (lisp Integer () completion-cost)
                     (lisp Integer () quality)
                     (lisp Integer () latency))))

(cl:defun cl-opt-cost ()     (coalton:coalton OptCost))
(cl:defun cl-opt-quality ()  (coalton:coalton OptQuality))
(cl:defun cl-opt-balanced () (coalton:coalton OptBalanced))
(cl:defun cl-opt-latency ()  (coalton:coalton OptLatency))

(cl:defun cl-recommend-model (profiles entries strategy)
  (coalton:coalton
   (recommend-model
    (lisp (List ModelCostProfile) () profiles)
    (lisp (List UsageEntry) () entries)
    (lisp OptimizationStrategy () strategy))))

(cl:defun cl-analyze-cost (profiles entries strategy)
  (coalton:coalton
   (analyze-cost
    (lisp (List ModelCostProfile) () profiles)
    (lisp (List UsageEntry) () entries)
    (lisp OptimizationStrategy () strategy))))

(cl:defun cl-rr-model (r)
  (coalton:coalton (rr-model (lisp RouteRecommendation () r))))

(cl:defun cl-rr-reason (r)
  (coalton:coalton (rr-reason (lisp RouteRecommendation () r))))

(cl:defun cl-rr-savings-pct (r)
  (coalton:coalton (rr-savings-pct (lisp RouteRecommendation () r))))

(cl:defun cl-rr-confidence-label (r)
  (coalton:coalton (confidence-label (rr-confidence (lisp RouteRecommendation () r)))))

(cl:defun cl-rr-strategy-label (r)
  (coalton:coalton (strategy-label (rr-strategy (lisp RouteRecommendation () r)))))

(cl:defun cl-ca-current-cost (a)
  (coalton:coalton (ca-current-cost (lisp CostAnalysis () a))))

(cl:defun cl-ca-optimal-cost (a)
  (coalton:coalton (ca-optimal-cost (lisp CostAnalysis () a))))

(cl:defun cl-ca-savings-pct (a)
  (coalton:coalton (ca-savings-pct (lisp CostAnalysis () a))))

(cl:defun cl-ca-strategy-label (a)
  (coalton:coalton (strategy-label (ca-strategy (lisp CostAnalysis () a)))))

(cl:defun cl-ca-recommendations (a)
  (coalton:coalton (ca-recommendations (lisp CostAnalysis () a))))
