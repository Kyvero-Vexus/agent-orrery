;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; analytics.lisp — TUI analytics cards: usage/cost/models/sub-agents
;;; Bead: agent-orrery-eb0.3.4
;;;
;;; Pure functional views. Time-window switching via card state.

(in-package #:orrery/tui)

;;; ─── Time Window ───

(deftype time-window () '(member :hour :day :week :all))

(declaim (ftype (function (keyword) (values keyword &optional)) next-time-window))
(defun next-time-window (current)
  "Cycle to next time window. Pure."
  (case current
    (:hour :day)
    (:day  :week)
    (:week :all)
    (:all  :hour)
    (otherwise :hour)))

(declaim (ftype (function (keyword) (values string &optional)) time-window-label))
(defun time-window-label (window)
  "Display label for a time window. Pure."
  (case window
    (:hour "Last Hour")
    (:day  "Last 24h")
    (:week "Last 7d")
    (:all  "All Time")
    (otherwise "?")))

;;; ─── Analytics Card ───

(defstruct (analytics-card (:conc-name ac-))
  "A single analytics metric card."
  (title    "" :type string)
  (value    "" :type string)
  (unit     "" :type string)
  (trend    :flat :type keyword)   ; :up :down :flat
  (window   :hour :type keyword))

(declaim (ftype (function (keyword) (values string &optional)) trend-indicator))
(defun trend-indicator (trend)
  "Render trend arrow. Pure."
  (case trend
    (:up   "↑")
    (:down "↓")
    (:flat "→")
    (otherwise "?")))

(declaim (ftype (function (analytics-card) (values string &optional)) render-card-line))
(defun render-card-line (card)
  "Render a single card as a one-line summary. Pure."
  (format nil "~A: ~A ~A ~A [~A]"
          (ac-title card)
          (ac-value card)
          (ac-unit card)
          (trend-indicator (ac-trend card))
          (time-window-label (ac-window card))))

;;; ─── Analytics Dashboard State ───

(defstruct (analytics-state (:conc-name as-))
  "State for the analytics cards panel."
  (window :hour :type keyword)
  (cards nil :type list)
  (selected-index 0 :type fixnum))

;;; ─── Card Builders (from domain data) ───

(declaim (ftype (function (list keyword) (values analytics-card &optional))
                build-token-usage-card))
(defun build-token-usage-card (sessions window)
  "Build token usage card from session records. Pure."
  (let ((total (reduce #'+ sessions :key #'sr-total-tokens :initial-value 0)))
    (make-analytics-card
     :title "Total Tokens"
     :value (format nil "~:D" total)
     :unit "tokens"
     :trend (cond ((> total 10000) :up)
                  ((< total 1000) :down)
                  (t :flat))
     :window window)))

(declaim (ftype (function (list keyword) (values analytics-card &optional))
                build-cost-card))
(defun build-cost-card (sessions window)
  "Build cost card from session records. Pure."
  (let ((total-cents (reduce #'+ sessions :key #'sr-estimated-cost-cents :initial-value 0)))
    (make-analytics-card
     :title "Total Cost"
     :value (format nil "$~,2F" (/ total-cents 100.0))
     :unit ""
     :trend (cond ((> total-cents 500) :up)
                  ((< total-cents 50) :down)
                  (t :flat))
     :window window)))

(declaim (ftype (function (list keyword) (values analytics-card &optional))
                build-model-distribution-card))
(defun build-model-distribution-card (sessions window)
  "Build model distribution card. Pure."
  (let* ((models (remove-duplicates (mapcar #'sr-model sessions) :test #'string=))
         (count (length models)))
    (make-analytics-card
     :title "Models Active"
     :value (format nil "~D" count)
     :unit "models"
     :trend :flat
     :window window)))

(declaim (ftype (function (list keyword) (values analytics-card &optional))
                build-session-count-card))
(defun build-session-count-card (sessions window)
  "Build session count card. Pure."
  (let ((active (count :active sessions :key #'sr-status))
        (total (length sessions)))
    (make-analytics-card
     :title "Sessions"
     :value (format nil "~D/~D active" active total)
     :unit ""
     :trend (cond ((> active 2) :up)
                  ((= active 0) :down)
                  (t :flat))
     :window window)))

;;; ─── Cost Optimizer Card (30m) ───

(declaim (ftype (function (list list keyword) (values analytics-card &optional))
                build-cost-optimizer-card))
(defun build-cost-optimizer-card (profiles entries window)
  "Build cost optimizer recommendation card. Pure.
PROFILES: list of Coalton ModelCostProfile, ENTRIES: list of Coalton UsageEntry."
  (declare (type keyword window) (optimize (safety 3)))
  (if (or (null profiles) (null entries))
      (make-analytics-card
       :title "Cost Optimizer"
       :value "No data"
       :unit "" :trend :flat :window window)
      (let* ((rec (orrery/coalton/core:cl-recommend-model
                   profiles entries (orrery/coalton/core:cl-opt-balanced)))
             (model (orrery/coalton/core:cl-rr-model rec))
             (confidence (orrery/coalton/core:cl-rr-confidence-label rec)))
        (make-analytics-card
         :title "Cost Optimizer"
         :value (format nil "~A (~A)" model confidence)
         :unit "recommended"
         :trend (cond ((string= confidence "high") :up)
                      ((string= confidence "low") :down)
                      (t :flat))
         :window window))))

;;; ─── Capacity Planner Card (30m) ───

(declaim (ftype (function (list list keyword) (values analytics-card &optional))
                build-capacity-planner-card))
(defun build-capacity-planner-card (thresholds values window)
  "Build capacity planner card. Pure.
THRESHOLDS: list of Coalton ThresholdSpec, VALUES: list of integers."
  (declare (type keyword window) (optimize (safety 3)))
  (if (or (null thresholds) (null values))
      (make-analytics-card
       :title "Capacity"
       :value "No data"
       :unit "" :trend :flat :window window)
      (let* ((plan (orrery/coalton/core:cl-build-capacity-plan thresholds values))
             (zone (orrery/coalton/core:cl-plan-worst-zone-label plan))
             (headroom (orrery/coalton/core:cl-plan-headroom-pct plan)))
        (make-analytics-card
         :title "Capacity"
         :value (format nil "~A (~D%)" zone headroom)
         :unit "headroom"
         :trend (cond ((string= zone "idle") :flat)
                      ((string= zone "normal") :flat)
                      ((string= zone "caution") :up)
                      (t :down))
         :window window))))

;;; ─── State Builders ───

(declaim (ftype (function (list keyword) (values analytics-state &optional))
                build-analytics-state))
(defun build-analytics-state (sessions window)
  "Build analytics state from session data. Pure."
  (make-analytics-state
   :window window
   :cards (list (build-token-usage-card sessions window)
                (build-cost-card sessions window)
                (build-model-distribution-card sessions window)
                (build-session-count-card sessions window))
   :selected-index 0))

(declaim (ftype (function (analytics-state) (values analytics-state &optional))
                cycle-analytics-window))
(defun cycle-analytics-window (state)
  "Cycle the time window and rebuild cards. Pure (uses existing card data)."
  (let ((new-window (next-time-window (as-window state))))
    (make-analytics-state
     :window new-window
     :cards (mapcar (lambda (c)
                      (make-analytics-card
                       :title (ac-title c) :value (ac-value c) :unit (ac-unit c)
                       :trend (ac-trend c) :window new-window))
                    (as-cards state))
     :selected-index (as-selected-index state))))

;;; ─── Render ───

(declaim (ftype (function (analytics-state) (values list &optional))
                render-analytics-lines))
(defun render-analytics-lines (state)
  "Render analytics cards as a list of display lines. Pure."
  (let ((lines (list (format nil "── Analytics [~A] ──" (time-window-label (as-window state))))))
    (let ((idx 0))
      (dolist (card (as-cards state))
        (push (format nil "~A ~A"
                      (if (= idx (as-selected-index state)) ">" " ")
                      (render-card-line card))
              lines)
        (incf idx)))
    (push "" lines)
    (push "Tab: cycle window | ↑↓: select card" lines)
    (nreverse lines)))
