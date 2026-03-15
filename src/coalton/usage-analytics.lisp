;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; usage-analytics.lisp — Coalton pure-core cost/usage analytics
;;;
;;; Typed, side-effect-free usage analytics: token counting, cost estimation,
;;; model distribution, time-series aggregation.

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Usage Entry ───

  (define-type UsageEntry
    (UsageEntry String    ; model name
                Integer   ; prompt tokens
                Integer   ; completion tokens
                Integer)) ; timestamp

  (declare ue-model (UsageEntry -> String))
  (define (ue-model e)
    (match e ((UsageEntry m _ _ _) m)))

  (declare ue-prompt-tokens (UsageEntry -> Integer))
  (define (ue-prompt-tokens e)
    (match e ((UsageEntry _ p _ _) p)))

  (declare ue-completion-tokens (UsageEntry -> Integer))
  (define (ue-completion-tokens e)
    (match e ((UsageEntry _ _ c _) c)))

  (declare ue-timestamp (UsageEntry -> Integer))
  (define (ue-timestamp e)
    (match e ((UsageEntry _ _ _ t) t)))

  (declare ue-total-tokens (UsageEntry -> Integer))
  (define (ue-total-tokens e)
    (+ (ue-prompt-tokens e) (ue-completion-tokens e)))

  (declare ue-cost-cents (UsageEntry -> Integer))
  (define (ue-cost-cents e)
    (estimate-cost-cents (ue-total-tokens e)))

  ;; ─── Model Rank ───

  (define-type ModelRank
    (ModelRank String    ; model name
              Integer   ; total tokens
              Integer)) ; permille (parts per thousand, avoids floats)

  (declare mr-model (ModelRank -> String))
  (define (mr-model r)
    (match r ((ModelRank m _ _) m)))

  (declare mr-total-tokens (ModelRank -> Integer))
  (define (mr-total-tokens r)
    (match r ((ModelRank _ t _) t)))

  (declare mr-permille (ModelRank -> Integer))
  (define (mr-permille r)
    (match r ((ModelRank _ _ p) p)))

  ;; ─── Usage Bucket ───

  (define-type UsageBucket
    (UsageBucket String          ; period label
                 (List UsageEntry) ; entries
                 Integer         ; total tokens
                 Integer))       ; total cost cents

  (declare bucket-period (UsageBucket -> String))
  (define (bucket-period b)
    (match b ((UsageBucket p _ _ _) p)))

  (declare bucket-entries (UsageBucket -> (List UsageEntry)))
  (define (bucket-entries b)
    (match b ((UsageBucket _ es _ _) es)))

  (declare bucket-total-tokens (UsageBucket -> Integer))
  (define (bucket-total-tokens b)
    (match b ((UsageBucket _ _ t _) t)))

  (declare bucket-total-cost (UsageBucket -> Integer))
  (define (bucket-total-cost b)
    (match b ((UsageBucket _ _ _ c) c)))

  ;; ─── Usage Summary ───

  (define-type UsageSummary
    (UsageSummary (List UsageBucket)  ; buckets
                  (List ModelRank)    ; top models
                  Integer             ; grand total tokens
                  Integer))           ; grand total cost cents

  (declare summary-buckets (UsageSummary -> (List UsageBucket)))
  (define (summary-buckets s)
    (match s ((UsageSummary bs _ _ _) bs)))

  (declare summary-top-models (UsageSummary -> (List ModelRank)))
  (define (summary-top-models s)
    (match s ((UsageSummary _ ms _ _) ms)))

  (declare summary-total-tokens (UsageSummary -> Integer))
  (define (summary-total-tokens s)
    (match s ((UsageSummary _ _ t _) t)))

  (declare summary-total-cost (UsageSummary -> Integer))
  (define (summary-total-cost s)
    (match s ((UsageSummary _ _ _ c) c)))

  ;; ─── Aggregation Helpers ───

  (declare sum-tokens ((List UsageEntry) -> Integer))
  (define (sum-tokens entries)
    (fold (fn (acc e) (+ acc (ue-total-tokens e))) 0 entries))

  (declare sum-cost ((List UsageEntry) -> Integer))
  (define (sum-cost entries)
    (fold (fn (acc e) (+ acc (ue-cost-cents e))) 0 entries))

  ;; ─── Aggregate Entries into Bucket ───

  (declare aggregate-entries (String -> (List UsageEntry) -> UsageBucket))
  (define (aggregate-entries period es)
    (UsageBucket period es (sum-tokens es) (sum-cost es)))

  ;; ─── Model Token Map (simple assoc list) ───

  (declare %update-model-tokens (String -> Integer -> (List (Tuple String Integer))
                                 -> (List (Tuple String Integer))))
  (define (%update-model-tokens model tokens alist)
    (match alist
      ((Nil) (Cons (Tuple model tokens) Nil))
      ((Cons (Tuple m t) rest)
       (if (== m model)
           (Cons (Tuple m (+ t tokens)) rest)
           (Cons (Tuple m t) (%update-model-tokens model tokens rest))))))

  (declare %entries->model-tokens ((List UsageEntry) -> (List (Tuple String Integer))))
  (define (%entries->model-tokens entries)
    (fold (fn (acc e) (%update-model-tokens (ue-model e) (ue-total-tokens e) acc))
          Nil entries))

  ;; ─── Insertion sort by tokens descending ───

  (declare %insert-ranked (ModelRank -> (List ModelRank) -> (List ModelRank)))
  (define (%insert-ranked r sorted)
    (match sorted
      ((Nil) (Cons r Nil))
      ((Cons head rest)
       (if (>= (mr-total-tokens r) (mr-total-tokens head))
           (Cons r sorted)
           (Cons head (%insert-ranked r rest))))))

  (declare %sort-ranks ((List ModelRank) -> (List ModelRank)))
  (define (%sort-ranks ranks)
    (fold (fn (sorted r) (%insert-ranked r sorted)) Nil ranks))

  ;; ─── Integer Division Helper ───

  (declare %idiv (Integer -> Integer -> Integer))
  (define (%idiv a b)
    (lisp Integer (a b) (cl:values (cl:truncate a b))))

  ;; ─── Top Models ───

  (declare top-models ((List UsageEntry) -> (List ModelRank)))
  (define (top-models entries)
    (let ((total (sum-tokens entries))
          (model-tokens (%entries->model-tokens entries)))
      (%sort-ranks
       (map (fn (pair)
              (match pair
                ((Tuple model tokens)
                 (ModelRank model tokens
                            (if (== total 0) 0
                                (%idiv (* tokens 1000) total))))))
            model-tokens))))

  ;; ─── Build Summary ───

  (declare build-usage-summary ((List UsageBucket) -> UsageSummary))
  (define (build-usage-summary buckets)
    (let ((all-entries (concatmap bucket-entries buckets))
          (grand-tokens (fold (fn (acc b) (+ acc (bucket-total-tokens b))) 0 buckets))
          (grand-cost (fold (fn (acc b) (+ acc (bucket-total-cost b))) 0 buckets)))
      (UsageSummary buckets (top-models all-entries) grand-tokens grand-cost))))

;;; ─── CL-callable bridge (in same package for Coalton interop) ───

(cl:defun cl-make-usage-entry (model prompt-tokens completion-tokens timestamp)
  "CL-callable constructor for UsageEntry."
  (coalton:coalton
   (usageentry
    (lisp String () model)
    (lisp Integer () prompt-tokens)
    (lisp Integer () completion-tokens)
    (lisp Integer () timestamp))))

(cl:defun cl-make-entry-list (cl-entries)
  "Convert CL list of UsageEntry values to Coalton list."
  (cl:if (cl:null cl-entries)
      (coalton:coalton Nil)
      (cl:let ((hd (cl:car cl-entries))
               (tl (cl-make-entry-list (cl:cdr cl-entries))))
        (coalton:coalton
         (Cons
          (lisp UsageEntry () hd)
          (lisp (List UsageEntry) () tl))))))

(cl:defun cl-aggregate-entries (period-label cl-entries)
  "CL-callable: aggregate CL list of entries into a UsageBucket."
  (cl:let ((coalton-list (cl-make-entry-list cl-entries)))
    (coalton:coalton
     (aggregate-entries
      (lisp String () period-label)
      (lisp (List UsageEntry) () coalton-list)))))

(cl:defun cl-build-summary (cl-buckets)
  "CL-callable: build UsageSummary from CL list of UsageBucket."
  (cl:let ((coalton-list (cl-%make-bucket-list cl-buckets)))
    (coalton:coalton
     (build-usage-summary
      (lisp (List UsageBucket) () coalton-list)))))

(cl:defun cl-%make-bucket-list (cl-buckets)
  "Convert CL list of UsageBucket to Coalton list."
  (cl:if (cl:null cl-buckets)
      (coalton:coalton Nil)
      (cl:let ((hd (cl:car cl-buckets))
               (tl (cl-%make-bucket-list (cl:cdr cl-buckets))))
        (coalton:coalton
         (Cons
          (lisp UsageBucket () hd)
          (lisp (List UsageBucket) () tl))))))

(cl:defun cl-summary-total-tokens (summary)
  "CL-callable: get total tokens from UsageSummary."
  (coalton:coalton
   (summary-total-tokens (lisp UsageSummary () summary))))

(cl:defun cl-summary-total-cost (summary)
  "CL-callable: get total cost from UsageSummary."
  (coalton:coalton
   (summary-total-cost (lisp UsageSummary () summary))))
