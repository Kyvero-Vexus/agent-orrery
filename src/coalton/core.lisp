;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; core.lisp — Coalton pure-core baseline transforms
;;;

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel
  ;; Normalize integer status codes into canonical status labels.
  ;; 0=active, 1=idle, 2=closed, otherwise unknown.
  (declare normalize-status-code (Integer -> String))
  (define (normalize-status-code code)
    (if (== code 0)
        "active"
        (if (== code 1)
            "idle"
            (if (== code 2)
                "closed"
                "unknown"))))

  ;; Deterministic integer cost model: ceil(tokens / 500)
  ;; Implemented purely via recursion to avoid floating point behavior.
  (declare estimate-cost-cents (Integer -> Integer))
  (define (estimate-cost-cents tokens)
    (if (<= tokens 0)
        0
        (+ 1 (estimate-cost-cents (- tokens 500))))))
