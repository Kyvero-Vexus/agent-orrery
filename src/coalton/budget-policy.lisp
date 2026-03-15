;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; budget-policy.lisp — Coalton pure budget policy evaluator
;;;
;;; Evaluates token/cost budget limits against usage summaries.
;;; All functions pure and total.

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Budget Period ───

  (repr :enum)
  (define-type BudgetPeriod
    BPDaily
    BPWeekly
    BPMonthly)

  ;; ─── Budget Scope ───

  (define-type BudgetScope
    GlobalScope
    (ModelScope String)
    (SessionScope String))

  ;; ─── Budget Limit ───

  (define-type BudgetLimit
    (BudgetLimit BudgetScope    ; scope
                 BudgetPeriod   ; period
                 Integer        ; max-tokens
                 Integer))      ; max-cost-cents

  (declare bl-scope (BudgetLimit -> BudgetScope))
  (define (bl-scope lim)
    (match lim ((BudgetLimit s _ _ _) s)))

  (declare bl-period (BudgetLimit -> BudgetPeriod))
  (define (bl-period lim)
    (match lim ((BudgetLimit _ p _ _) p)))

  (declare bl-max-tokens (BudgetLimit -> Integer))
  (define (bl-max-tokens lim)
    (match lim ((BudgetLimit _ _ t _) t)))

  (declare bl-max-cost (BudgetLimit -> Integer))
  (define (bl-max-cost lim)
    (match lim ((BudgetLimit _ _ _ c) c)))

  ;; ─── Threshold Level ───

  (repr :enum)
  (define-type ThresholdLevel
    TLOk
    TLWarning
    TLCritical
    TLExceeded)

  ;; ─── Budget Verdict ───

  (define-type BudgetVerdict
    (BudgetVerdict BudgetScope     ; scope evaluated
                   ThresholdLevel  ; result
                   Integer         ; actual-tokens
                   Integer         ; limit-tokens
                   Integer))       ; utilization-permille

  (declare bv-scope (BudgetVerdict -> BudgetScope))
  (define (bv-scope v)
    (match v ((BudgetVerdict s _ _ _ _) s)))

  (declare bv-level (BudgetVerdict -> ThresholdLevel))
  (define (bv-level v)
    (match v ((BudgetVerdict _ l _ _ _) l)))

  (declare bv-actual (BudgetVerdict -> Integer))
  (define (bv-actual v)
    (match v ((BudgetVerdict _ _ a _ _) a)))

  (declare bv-limit-tokens (BudgetVerdict -> Integer))
  (define (bv-limit-tokens v)
    (match v ((BudgetVerdict _ _ _ l _) l)))

  (declare bv-utilization (BudgetVerdict -> Integer))
  (define (bv-utilization v)
    (match v ((BudgetVerdict _ _ _ _ u) u)))

  ;; ─── Threshold Classification ───

  (declare classify-threshold (Integer -> ThresholdLevel))
  (define (classify-threshold permille)
    (if (>= permille 1000) TLExceeded
        (if (>= permille 900) TLCritical
            (if (>= permille 700) TLWarning
                TLOk))))

  ;; ─── Integer Division Helper ───

  (declare %budget-idiv (Integer -> Integer -> Integer))
  (define (%budget-idiv a b)
    (lisp Integer (a b) (cl:values (cl:truncate a b))))

  ;; ─── Evaluate Single Limit ───

  (declare evaluate-limit (BudgetLimit -> Integer -> BudgetVerdict))
  (define (evaluate-limit lim actual-tokens)
    (let ((max-tok (bl-max-tokens lim))
          (util (if (<= max-tok 0) 1000
                    (%budget-idiv (* actual-tokens 1000) max-tok))))
      (BudgetVerdict (bl-scope lim)
                     (classify-threshold util)
                     actual-tokens
                     max-tok
                     util)))

  ;; ─── Evaluate Policy (list of limits) ───

  (declare evaluate-policy-limits ((List BudgetLimit) -> Integer -> (List BudgetVerdict)))
  (define (evaluate-policy-limits limits actual-tokens)
    (map (fn (lim) (evaluate-limit lim actual-tokens)) limits))

  ;; ─── Worst Verdict ───

  (declare %level-ord (ThresholdLevel -> Integer))
  (define (%level-ord lvl)
    (match lvl
      ((TLOk) 0)
      ((TLWarning) 1)
      ((TLCritical) 2)
      ((TLExceeded) 3)))

  (declare worst-level ((List BudgetVerdict) -> ThresholdLevel))
  (define (worst-level verdicts)
    (fold (fn (worst v)
            (if (> (%level-ord (bv-level v)) (%level-ord worst))
                (bv-level v)
                worst))
          TLOk verdicts))

  ;; ─── Escalation Hint ───

  (declare verdict-hint (BudgetVerdict -> String))
  (define (verdict-hint v)
    (match (bv-level v)
      ((TLOk) "Within budget")
      ((TLWarning) "Approaching budget limit")
      ((TLCritical) "Near budget limit — consider throttling")
      ((TLExceeded) "Budget exceeded — action required"))))

;;; ─── CL-callable bridge ───

(cl:defun cl-make-budget-limit (scope-keyword scope-name period-keyword max-tokens max-cost)
  "CL-callable: construct BudgetLimit.
   SCOPE-KEYWORD: :global, :model, :session
   PERIOD-KEYWORD: :daily, :weekly, :monthly"
  (cl:let ((scope (cl:ecase scope-keyword
                    (:global (coalton:coalton globalscope))
                    (:model (coalton:coalton (modelscope (lisp String () scope-name))))
                    (:session (coalton:coalton (sessionscope (lisp String () scope-name))))))
           (period (cl:ecase period-keyword
                     (:daily (coalton:coalton bpdaily))
                     (:weekly (coalton:coalton bpweekly))
                     (:monthly (coalton:coalton bpmonthly)))))
    (coalton:coalton
     (budgetlimit (lisp BudgetScope () scope)
                  (lisp BudgetPeriod () period)
                  (lisp Integer () max-tokens)
                  (lisp Integer () max-cost)))))

(cl:defun cl-%make-limit-list (cl-limits)
  "Convert CL list of BudgetLimit to Coalton list."
  (cl:if (cl:null cl-limits)
      (coalton:coalton Nil)
      (cl:let ((item0 (cl:car cl-limits))
               (rest0 (cl-%make-limit-list (cl:cdr cl-limits))))
        (coalton:coalton
         (Cons (lisp BudgetLimit () item0)
               (lisp (List BudgetLimit) () rest0))))))

(cl:defun cl-evaluate-policy (cl-limits actual-tokens)
  "CL-callable: evaluate list of limits, return CL list of verdicts."
  (cl:let* ((coalton-limits (cl-%make-limit-list cl-limits))
            (coalton-verdicts
             (coalton:coalton
              (evaluate-policy-limits
               (lisp (List BudgetLimit) () coalton-limits)
               (lisp Integer () actual-tokens)))))
    (verdicts->cl-list coalton-verdicts)))

(cl:defun verdicts->cl-list (coalton-list)
  "Convert Coalton verdict list to CL list."
  (cl:let ((len (coalton:coalton
                 (coalton-library/list:length
                  (lisp (List BudgetVerdict) () coalton-list)))))
    (cl:if (cl:= len 0)
        cl:nil
        (cl:let ((vhead (coalton:coalton
                           (coalton-library/list:head
                            (lisp (List BudgetVerdict) () coalton-list))))
                 (vtail (coalton:coalton
                          (coalton-library/list:tail
                           (lisp (List BudgetVerdict) () coalton-list)))))
          (cl:cons vhead (verdicts->cl-list vtail))))))

(cl:defun cl-verdict-level-keyword (verdict)
  "CL-callable: return ThresholdLevel as CL keyword."
  (cl:let ((lvl (coalton:coalton
                 (bv-level (lisp BudgetVerdict () verdict)))))
    (cl:let ((ord (coalton:coalton
                   (%level-ord (lisp ThresholdLevel () lvl)))))
      (cl:ecase ord
        (0 :ok)
        (1 :warning)
        (2 :critical)
        (3 :exceeded)))))

(cl:defun cl-verdict-hint (verdict)
  "CL-callable: return escalation hint string."
  (coalton:coalton (verdict-hint (lisp BudgetVerdict () verdict))))

(cl:defun cl-verdict-utilization (verdict)
  "CL-callable: return utilization permille as fixnum."
  (coalton:coalton (bv-utilization (lisp BudgetVerdict () verdict))))

(cl:defun cl-verdict-actual (verdict)
  "CL-callable: return actual tokens as fixnum."
  (coalton:coalton (bv-actual (lisp BudgetVerdict () verdict))))
