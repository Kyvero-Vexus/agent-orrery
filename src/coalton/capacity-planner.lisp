;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capacity-planner.lisp — Coalton pure capacity planning from scenario projections
;;;
;;; Computes auto-scaling thresholds with headroom calculations.
;;; All functions pure and total.
;;;
;;; Bead: agent-orrery-j9c

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Capacity Band ───

  (repr :enum)
  (define-type CapacityZone
    "Current capacity zone."
    ZoneIdle       ; well below any threshold
    ZoneNormal     ; within normal operating range
    ZoneCaution    ; approaching a threshold
    ZoneCritical   ; at or above threshold
    ZoneOverflow)  ; exceeds maximum capacity

  (declare zone-label (CapacityZone -> String))
  (define (zone-label z)
    (match z
      ((ZoneIdle)     "idle")
      ((ZoneNormal)   "normal")
      ((ZoneCaution)  "caution")
      ((ZoneCritical) "critical")
      ((ZoneOverflow) "overflow")))

  (declare zone-severity (CapacityZone -> Integer))
  (define (zone-severity z)
    (match z
      ((ZoneIdle)     0)
      ((ZoneNormal)   1)
      ((ZoneCaution)  2)
      ((ZoneCritical) 3)
      ((ZoneOverflow) 4)))

  ;; ─── Threshold Spec ───

  (define-type ThresholdSpec
    "A named capacity threshold."
    (ThresholdSpec String    ; metric name (e.g., "sessions", "tokens-per-hour")
                   Integer   ; warning threshold
                   Integer   ; critical threshold
                   Integer)) ; maximum (overflow)

  (declare ts-metric (ThresholdSpec -> String))
  (define (ts-metric t)
    (match t ((ThresholdSpec m _ _ _) m)))

  (declare ts-warning (ThresholdSpec -> Integer))
  (define (ts-warning t)
    (match t ((ThresholdSpec _ w _ _) w)))

  (declare ts-critical (ThresholdSpec -> Integer))
  (define (ts-critical t)
    (match t ((ThresholdSpec _ _ c _) c)))

  (declare ts-maximum (ThresholdSpec -> Integer))
  (define (ts-maximum t)
    (match t ((ThresholdSpec _ _ _ m) m)))

  ;; ─── Capacity Assessment ───

  (define-type CapacityAssessment
    "Assessment of one metric against its thresholds."
    (CapacityAssessment String        ; metric name
                        Integer       ; current value
                        CapacityZone  ; zone
                        Integer       ; headroom (units until next threshold)
                        Integer       ; utilization-pct (0-100+)
                        String))      ; recommendation

  (declare assess-metric (CapacityAssessment -> String))
  (define (assess-metric a)
    (match a ((CapacityAssessment m _ _ _ _ _) m)))

  (declare assess-value (CapacityAssessment -> Integer))
  (define (assess-value a)
    (match a ((CapacityAssessment _ v _ _ _ _) v)))

  (declare assess-zone (CapacityAssessment -> CapacityZone))
  (define (assess-zone a)
    (match a ((CapacityAssessment _ _ z _ _ _) z)))

  (declare assess-headroom (CapacityAssessment -> Integer))
  (define (assess-headroom a)
    (match a ((CapacityAssessment _ _ _ h _ _) h)))

  (declare assess-util-pct (CapacityAssessment -> Integer))
  (define (assess-util-pct a)
    (match a ((CapacityAssessment _ _ _ _ u _) u)))

  (declare assess-recommendation (CapacityAssessment -> String))
  (define (assess-recommendation a)
    (match a ((CapacityAssessment _ _ _ _ _ r) r)))

  ;; ─── Capacity Plan ───

  (define-type CapacityPlan
    "Complete capacity plan with all metric assessments."
    (CapacityPlan (List CapacityAssessment) ; assessments
                  CapacityZone              ; worst-zone
                  Integer))                 ; overall-headroom-pct

  (declare plan-assessments (CapacityPlan -> (List CapacityAssessment)))
  (define (plan-assessments p)
    (match p ((CapacityPlan as _ _) as)))

  (declare plan-worst-zone (CapacityPlan -> CapacityZone))
  (define (plan-worst-zone p)
    (match p ((CapacityPlan _ z _) z)))

  (declare plan-headroom-pct (CapacityPlan -> Integer))
  (define (plan-headroom-pct p)
    (match p ((CapacityPlan _ _ h) h)))

  ;; ─── Core Logic ───

  (declare %cp-safe-div (Integer -> Integer -> Integer))
  (define (%cp-safe-div num denom)
    (if (== denom 0) 0 (lisp Integer (num denom) (cl:values (cl:truncate num denom)))))

  (declare classify-zone (Integer -> ThresholdSpec -> CapacityZone))
  (define (classify-zone value spec)
    (cond
      ((>= value (ts-maximum spec))  ZoneOverflow)
      ((>= value (ts-critical spec)) ZoneCritical)
      ((>= value (ts-warning spec))  ZoneCaution)
      ((>= value (%cp-safe-div (ts-warning spec) 2)) ZoneNormal)
      (True                          ZoneIdle)))

  (declare %headroom (Integer -> ThresholdSpec -> Integer))
  (define (%headroom value spec)
    "Units of headroom until next threshold breach."
    (cond
      ((>= value (ts-maximum spec))  0)
      ((>= value (ts-critical spec)) (- (ts-maximum spec) value))
      ((>= value (ts-warning spec))  (- (ts-critical spec) value))
      (True                          (- (ts-warning spec) value))))

  (declare %recommendation (CapacityZone -> String))
  (define (%recommendation zone)
    (match zone
      ((ZoneIdle)     "No action needed")
      ((ZoneNormal)   "Operating normally")
      ((ZoneCaution)  "Monitor closely; consider scaling")
      ((ZoneCritical) "Scale up immediately")
      ((ZoneOverflow) "Emergency: capacity exceeded")))

  (declare evaluate-threshold (Integer -> ThresholdSpec -> CapacityAssessment))
  (define (evaluate-threshold value spec)
    "Evaluate a single metric against its threshold spec."
    (let ((zone (classify-zone value spec))
          (headroom (%headroom value spec))
          (util-pct (%cp-safe-div (* value 100) (ts-maximum spec))))
      (CapacityAssessment
       (ts-metric spec)
       value
       zone
       headroom
       util-pct
       (%recommendation zone))))

  (declare %worst-zone ((List CapacityAssessment) -> CapacityZone))
  (define (%worst-zone assessments)
    (fold (fn (worst a)
            (if (> (zone-severity (assess-zone a)) (zone-severity worst))
                (assess-zone a)
                worst))
          ZoneIdle
          assessments))

  (declare %min-headroom-pct ((List CapacityAssessment) -> Integer))
  (define (%min-headroom-pct assessments)
    (fold (fn (min-pct a)
            (let ((remaining (- 100 (assess-util-pct a))))
              (if (< remaining min-pct) remaining min-pct)))
          100
          assessments))

  (declare build-capacity-plan ((List ThresholdSpec) -> (List Integer) -> CapacityPlan))
  (define (build-capacity-plan specs values)
    "Build a capacity plan from threshold specs and current values."
    (let ((assessments (zipWith evaluate-threshold values specs)))
      (CapacityPlan
       assessments
       (%worst-zone assessments)
       (%min-headroom-pct assessments))))

  ;; ─── Default Thresholds ───

  (declare default-capacity-thresholds (Unit -> (List ThresholdSpec)))
  (define (default-capacity-thresholds _u)
    (Cons (ThresholdSpec "sessions" 500 800 1000)
          (Cons (ThresholdSpec "tokens-per-hour" 50000 80000 100000)
                (Cons (ThresholdSpec "cost-per-hour" 5000 8000 10000)
                      (Cons (ThresholdSpec "cron-per-hour" 100 200 300)
                            (the (List ThresholdSpec) Nil)))))))

;;; ─── CL Bridge ───

(cl:defun cl-make-threshold-spec (metric warning critical maximum)
  (coalton:coalton
   (ThresholdSpec (lisp String () metric)
                  (lisp Integer () warning)
                  (lisp Integer () critical)
                  (lisp Integer () maximum))))

(cl:defun cl-default-capacity-thresholds ()
  (coalton:coalton (default-capacity-thresholds Unit)))

(cl:defun cl-evaluate-threshold (value spec)
  (coalton:coalton
   (evaluate-threshold (lisp Integer () value)
                       (lisp ThresholdSpec () spec))))

(cl:defun cl-build-capacity-plan (specs values)
  (coalton:coalton
   (build-capacity-plan (lisp (List ThresholdSpec) () specs)
                        (lisp (List Integer) () values))))

(cl:defun cl-assess-metric-name (a)
  (coalton:coalton (assess-metric (lisp CapacityAssessment () a))))

(cl:defun cl-assess-value (a)
  (coalton:coalton (assess-value (lisp CapacityAssessment () a))))

(cl:defun cl-assess-zone-label (a)
  (coalton:coalton (zone-label (assess-zone (lisp CapacityAssessment () a)))))

(cl:defun cl-assess-headroom (a)
  (coalton:coalton (assess-headroom (lisp CapacityAssessment () a))))

(cl:defun cl-assess-util-pct (a)
  (coalton:coalton (assess-util-pct (lisp CapacityAssessment () a))))

(cl:defun cl-assess-recommendation (a)
  (coalton:coalton (assess-recommendation (lisp CapacityAssessment () a))))

(cl:defun cl-plan-worst-zone-label (p)
  (coalton:coalton (zone-label (plan-worst-zone (lisp CapacityPlan () p)))))

(cl:defun cl-plan-headroom-pct (p)
  (coalton:coalton (plan-headroom-pct (lisp CapacityPlan () p))))

(cl:defun cl-plan-assessments (p)
  (coalton:coalton (plan-assessments (lisp CapacityPlan () p))))
