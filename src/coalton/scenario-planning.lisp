;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; scenario-planning.lisp — Coalton pure scenario-planning core
;;;
;;; What-if simulation for budget, capacity, model-mix, and cron cadence.
;;; All functions pure and total. No IO.
;;;
;;; Bead: agent-orrery-20d

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Scenario Parameters ───

  (define-type ScenarioParam
    "One axis of a what-if scenario."
    (SPSessionVolume Integer)       ; projected session count
    (SPModelMix (List ModelRank))   ; projected model distribution
    (SPCronCadence Integer)         ; projected cron jobs/hour
    (SPBudgetCap Integer)           ; projected budget cap (cents)
    (SPTokenCeiling Integer))       ; projected token ceiling

  (declare sp-tag (ScenarioParam -> String))
  (define (sp-tag p)
    (match p
      ((SPSessionVolume _)  "session-volume")
      ((SPModelMix _)       "model-mix")
      ((SPCronCadence _)    "cron-cadence")
      ((SPBudgetCap _)      "budget-cap")
      ((SPTokenCeiling _)   "token-ceiling")))

  ;; ─── Scenario Definition ───

  (define-type Scenario
    "A named what-if scenario with parameter overrides."
    (Scenario String                ; name
              (List ScenarioParam)  ; parameter overrides
              Integer))             ; horizon-hours

  (declare scenario-name (Scenario -> String))
  (define (scenario-name s)
    (match s ((Scenario n _ _) n)))

  (declare scenario-params (Scenario -> (List ScenarioParam)))
  (define (scenario-params s)
    (match s ((Scenario _ ps _) ps)))

  (declare scenario-horizon (Scenario -> Integer))
  (define (scenario-horizon s)
    (match s ((Scenario _ _ h) h)))

  ;; ─── Baseline Snapshot ───

  (define-type BaselineSnapshot
    "Current observed state for projection."
    (BaselineSnapshot Integer          ; current-sessions
                      Integer          ; current-tokens-per-hour
                      Integer          ; current-cost-per-hour (cents)
                      Integer          ; current-cron-per-hour
                      (List ModelRank) ; current model distribution
                      Integer))        ; budget-cap (cents)

  (declare bs-sessions (BaselineSnapshot -> Integer))
  (define (bs-sessions b)
    (match b ((BaselineSnapshot s _ _ _ _ _) s)))

  (declare bs-tokens-per-hour (BaselineSnapshot -> Integer))
  (define (bs-tokens-per-hour b)
    (match b ((BaselineSnapshot _ t _ _ _ _) t)))

  (declare bs-cost-per-hour (BaselineSnapshot -> Integer))
  (define (bs-cost-per-hour b)
    (match b ((BaselineSnapshot _ _ c _ _ _) c)))

  (declare bs-cron-per-hour (BaselineSnapshot -> Integer))
  (define (bs-cron-per-hour b)
    (match b ((BaselineSnapshot _ _ _ cr _ _) cr)))

  (declare bs-model-mix (BaselineSnapshot -> (List ModelRank)))
  (define (bs-model-mix b)
    (match b ((BaselineSnapshot _ _ _ _ m _) m)))

  (declare bs-budget-cap (BaselineSnapshot -> Integer))
  (define (bs-budget-cap b)
    (match b ((BaselineSnapshot _ _ _ _ _ cap) cap)))

  ;; ─── Projection Results ───

  (define-type ProjectionSignal
    "Recommendation signal from scenario analysis."
    SignalOk            ; within budget, no issues
    SignalCaution       ; approaching limits
    SignalOverBudget    ; exceeds budget cap
    SignalOverCapacity  ; exceeds token ceiling
    SignalMixImbalance) ; model mix heavily skewed

  (declare signal-label (ProjectionSignal -> String))
  (define (signal-label sig)
    (match sig
      ((SignalOk)           "ok")
      ((SignalCaution)      "caution")
      ((SignalOverBudget)   "over-budget")
      ((SignalOverCapacity) "over-capacity")
      ((SignalMixImbalance) "mix-imbalance")))

  (define-type ProjectionResult
    "Deterministic projection from a scenario."
    (ProjectionResult String              ; scenario-name
                      Integer             ; projected-total-tokens
                      Integer             ; projected-total-cost (cents)
                      Integer             ; projected-sessions
                      Integer             ; projected-cron-invocations
                      Integer             ; budget-utilization-pct
                      (List ProjectionSignal))) ; signals

  (declare pr-scenario-name (ProjectionResult -> String))
  (define (pr-scenario-name r)
    (match r ((ProjectionResult n _ _ _ _ _ _) n)))

  (declare pr-total-tokens (ProjectionResult -> Integer))
  (define (pr-total-tokens r)
    (match r ((ProjectionResult _ t _ _ _ _ _) t)))

  (declare pr-total-cost (ProjectionResult -> Integer))
  (define (pr-total-cost r)
    (match r ((ProjectionResult _ _ c _ _ _ _) c)))

  (declare pr-sessions (ProjectionResult -> Integer))
  (define (pr-sessions r)
    (match r ((ProjectionResult _ _ _ s _ _ _) s)))

  (declare pr-cron-invocations (ProjectionResult -> Integer))
  (define (pr-cron-invocations r)
    (match r ((ProjectionResult _ _ _ _ cr _ _) cr)))

  (declare pr-budget-util-pct (ProjectionResult -> Integer))
  (define (pr-budget-util-pct r)
    (match r ((ProjectionResult _ _ _ _ _ u _) u)))

  (declare pr-signals (ProjectionResult -> (List ProjectionSignal)))
  (define (pr-signals r)
    (match r ((ProjectionResult _ _ _ _ _ _ sigs) sigs)))

  ;; ─── Projection Logic ───

  (declare %safe-div (Integer -> Integer -> Integer))
  (define (%safe-div num denom)
    (if (== denom 0) 0 (lisp Integer (num denom) (cl:values (cl:truncate num denom)))))

  (declare %extract-session-volume (BaselineSnapshot -> (List ScenarioParam) -> Integer))
  (define (%extract-session-volume baseline params)
    (match params
      ((Nil) (bs-sessions baseline))
      ((Cons (SPSessionVolume v) _) v)
      ((Cons _ rest) (%extract-session-volume baseline rest))))

  (declare %extract-budget-cap (BaselineSnapshot -> (List ScenarioParam) -> Integer))
  (define (%extract-budget-cap baseline params)
    (match params
      ((Nil) (bs-budget-cap baseline))
      ((Cons (SPBudgetCap v) _) v)
      ((Cons _ rest) (%extract-budget-cap baseline rest))))

  (declare %extract-token-ceiling (BaselineSnapshot -> (List ScenarioParam) -> Integer))
  (define (%extract-token-ceiling baseline params)
    (match params
      ((Nil) 0)
      ((Cons (SPTokenCeiling v) _) v)
      ((Cons _ rest) (%extract-token-ceiling baseline rest))))

  (declare %extract-cron-cadence (BaselineSnapshot -> (List ScenarioParam) -> Integer))
  (define (%extract-cron-cadence baseline params)
    (match params
      ((Nil) (bs-cron-per-hour baseline))
      ((Cons (SPCronCadence v) _) v)
      ((Cons _ rest) (%extract-cron-cadence baseline rest))))

  (declare %extract-model-mix (BaselineSnapshot -> (List ScenarioParam) -> (List ModelRank)))
  (define (%extract-model-mix baseline params)
    (match params
      ((Nil) (bs-model-mix baseline))
      ((Cons (SPModelMix m) _) m)
      ((Cons _ rest) (%extract-model-mix baseline rest))))

  (declare %max-permille ((List ModelRank) -> Integer))
  (define (%max-permille ranks)
    (fold (fn (acc r) (if (> (mr-permille r) acc) (mr-permille r) acc))
          0
          ranks))

  (declare %signal-singleton (ProjectionSignal -> (List ProjectionSignal)))
  (define (%signal-singleton s)
    (Cons s (the (List ProjectionSignal) Nil)))

  (declare %classify-signals (Integer -> Integer -> Integer -> Integer -> (List ModelRank) -> (List ProjectionSignal)))
  (define (%classify-signals total-cost budget-cap total-tokens token-ceiling model-mix)
    (let ((budget-util (if (== budget-cap 0) 0 (%safe-div (* total-cost 100) budget-cap)))
          (over-budget (if (> budget-cap 0) (> total-cost budget-cap) False))
          (over-capacity (if (> token-ceiling 0) (> total-tokens token-ceiling) False))
          (caution (if (> budget-cap 0) (> budget-util 80) False))
          (imbalanced (> (%max-permille model-mix) 800)))
      (let ((base (if over-budget
                      (%signal-singleton SignalOverBudget)
                      (if caution
                          (%signal-singleton SignalCaution)
                          (%signal-singleton SignalOk)))))
        (let ((with-cap (if over-capacity
                            (Cons SignalOverCapacity base)
                            base)))
          (if imbalanced
              (Cons SignalMixImbalance with-cap)
              with-cap)))))

  (declare run-scenario (BaselineSnapshot -> Scenario -> ProjectionResult))
  (define (run-scenario baseline scenario)
    "Project a scenario against the baseline. Pure, deterministic."
    (let ((params (scenario-params scenario))
          (horizon (scenario-horizon scenario))
          (sessions (%extract-session-volume baseline params))
          (cron-rate (%extract-cron-cadence baseline params))
          (budget-cap (%extract-budget-cap baseline params))
          (token-ceiling (%extract-token-ceiling baseline params))
          (model-mix (%extract-model-mix baseline params)))
      ;; Scale tokens/cost proportionally to session volume change
      (let ((scale-factor (if (== (bs-sessions baseline) 0)
                              100
                              (%safe-div (* sessions 100) (bs-sessions baseline)))))
        (let ((proj-tokens-hour (%safe-div (* (bs-tokens-per-hour baseline) scale-factor) 100))
              (proj-cost-hour (%safe-div (* (bs-cost-per-hour baseline) scale-factor) 100))
              (proj-cron (* cron-rate horizon)))
          (let ((total-tokens (* proj-tokens-hour horizon))
                (total-cost (* proj-cost-hour horizon)))
            (let ((budget-util-pct (if (== budget-cap 0) 0 (%safe-div (* total-cost 100) budget-cap)))
                  (signals (%classify-signals total-cost budget-cap total-tokens token-ceiling model-mix)))
              (ProjectionResult
               (scenario-name scenario)
               total-tokens
               total-cost
               sessions
               proj-cron
               budget-util-pct
               signals)))))))

  (declare run-scenarios (BaselineSnapshot -> (List Scenario) -> (List ProjectionResult)))
  (define (run-scenarios baseline scenarios)
    "Run multiple scenarios. Pure batch projection."
    (map (run-scenario baseline) scenarios)))

;;; ─── CL Bridge ───

(cl:defun cl-make-baseline-snapshot (sessions tokens-per-hour cost-per-hour cron-per-hour model-ranks budget-cap)
  "CL-callable: build a BaselineSnapshot."
  (coalton:coalton
   (BaselineSnapshot
    (lisp Integer () sessions)
    (lisp Integer () tokens-per-hour)
    (lisp Integer () cost-per-hour)
    (lisp Integer () cron-per-hour)
    (lisp (List ModelRank) () model-ranks)
    (lisp Integer () budget-cap))))

(cl:defun cl-make-scenario (name params horizon)
  "CL-callable: build a Scenario."
  (coalton:coalton
   (Scenario
    (lisp String () name)
    (lisp (List ScenarioParam) () params)
    (lisp Integer () horizon))))

(cl:defun cl-sp-session-volume (n)
  (coalton:coalton (SPSessionVolume (lisp Integer () n))))

(cl:defun cl-sp-budget-cap (n)
  (coalton:coalton (SPBudgetCap (lisp Integer () n))))

(cl:defun cl-sp-token-ceiling (n)
  (coalton:coalton (SPTokenCeiling (lisp Integer () n))))

(cl:defun cl-sp-cron-cadence (n)
  (coalton:coalton (SPCronCadence (lisp Integer () n))))

(cl:defun cl-sp-model-mix (ranks)
  (coalton:coalton (SPModelMix (lisp (List ModelRank) () ranks))))

(cl:defun cl-run-scenario (baseline scenario)
  "CL-callable: run one scenario projection."
  (coalton:coalton
   (run-scenario
    (lisp BaselineSnapshot () baseline)
    (lisp Scenario () scenario))))

(cl:defun cl-run-scenarios (baseline scenarios)
  "CL-callable: batch projection."
  (coalton:coalton
   (run-scenarios
    (lisp BaselineSnapshot () baseline)
    (lisp (List Scenario) () scenarios))))

(cl:defun cl-projection-scenario-name (r)
  (coalton:coalton (pr-scenario-name (lisp ProjectionResult () r))))

(cl:defun cl-projection-total-tokens (r)
  (coalton:coalton (pr-total-tokens (lisp ProjectionResult () r))))

(cl:defun cl-projection-total-cost (r)
  (coalton:coalton (pr-total-cost (lisp ProjectionResult () r))))

(cl:defun cl-projection-sessions (r)
  (coalton:coalton (pr-sessions (lisp ProjectionResult () r))))

(cl:defun cl-projection-cron-invocations (r)
  (coalton:coalton (pr-cron-invocations (lisp ProjectionResult () r))))

(cl:defun cl-projection-budget-util-pct (r)
  (coalton:coalton (pr-budget-util-pct (lisp ProjectionResult () r))))

(cl:defun cl-projection-signal-labels (r)
  "CL-callable: return signal labels as list of strings."
  (coalton:coalton
   (map signal-label (pr-signals (lisp ProjectionResult () r)))))
