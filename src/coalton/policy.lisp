;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; policy.lisp — Coalton-backed capability policy algebra
;;;
;;; Defines typed policy decisions (Allow/Deny/Ask) with algebraic
;;; combination rules consumed by CL-side capability-mapper executors.

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel
  ;; Policy decision ADT: the three possible outcomes
  (repr :enum)
  (define-type PolicyDecision
    Allow
    Deny
    Ask)

  ;; Policy rule: maps an operation name to a decision
  (define-type PolicyRule
    (PolicyRule String PolicyDecision))

  ;; Policy set: ordered list of rules (first match wins)
  (define-type PolicySet
    (PolicySet (List PolicyRule)))

  ;; Extract rule operation name
  (declare rule-operation (PolicyRule -> String))
  (define (rule-operation r)
    (match r
      ((PolicyRule op _) op)))

  ;; Extract rule decision
  (declare rule-decision (PolicyRule -> PolicyDecision))
  (define (rule-decision r)
    (match r
      ((PolicyRule _ d) d)))

  ;; Combine two decisions: Deny wins over Ask wins over Allow
  (declare combine-decisions (PolicyDecision -> PolicyDecision -> PolicyDecision))
  (define (combine-decisions a b)
    (match a
      ((Deny) Deny)
      ((Ask) (match b
               ((Deny) Deny)
               (_ Ask)))
      ((Allow) b)))

  ;; Look up decision for an operation in a policy set (first match wins)
  (declare evaluate-policy (PolicySet -> String -> PolicyDecision))
  (define (evaluate-policy ps op)
    (match ps
      ((PolicySet rules)
       (%find-rule rules op))))

  (declare %find-rule ((List PolicyRule) -> String -> PolicyDecision))
  (define (%find-rule rules op)
    (match rules
      ((Nil) Deny)
      ((Cons r rest)
       (if (== (rule-operation r) op)
           (rule-decision r)
           (%find-rule rest op)))))

  ;; Merge two policy sets: for each operation, combine decisions
  ;; (restrictive merge — Deny dominates)
  (declare merge-policies (PolicySet -> PolicySet -> String -> PolicyDecision))
  (define (merge-policies ps1 ps2 op)
    (combine-decisions (evaluate-policy ps1 op)
                       (evaluate-policy ps2 op)))

  ;; Check if a decision permits execution
  (declare decision-permits-p (PolicyDecision -> Boolean))
  (define (decision-permits-p d)
    (match d
      ((Allow) True)
      (_ False)))

  ;; Build a policy set from operation-decision pairs
  (declare make-policy ((List (Tuple String PolicyDecision)) -> PolicySet))
  (define (make-policy pairs)
    (PolicySet (map (fn (pair)
                      (PolicyRule (fst pair) (snd pair)))
                    pairs))))
