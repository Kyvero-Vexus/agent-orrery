;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; v2-panes.lisp — McCLIM panes for new v2 Coalton modules
;;;
;;; Pure display functions for audit-trail, cost-optimizer,
;;; capacity-planner, and session-analytics.
;;;
;;; Bead: agent-orrery-4qy

(in-package #:orrery/mcclim)

;;; ─── Cost Optimizer Pane ───

(defun display-cost-optimizer (frame pane)
  "Display cost optimizer recommendations."
  (declare (ignore frame) (optimize (safety 3)))
  (formatting-table (pane)
    (formatting-row (pane)
      (formatting-cell (pane) (format pane "Model"))
      (formatting-cell (pane) (format pane "Strategy"))
      (formatting-cell (pane) (format pane "Confidence"))
      (formatting-cell (pane) (format pane "Savings %")))
    ;; Placeholder row showing balanced recommendation
    (let* ((profiles (list (orrery/coalton/core:cl-make-model-cost-profile "gpt-4" 30 60 900 300)
                           (orrery/coalton/core:cl-make-model-cost-profile "claude-3" 20 40 850 200)
                           (orrery/coalton/core:cl-make-model-cost-profile "llama-70b" 5 10 700 400)))
           (entries (loop for i from 1 to 20
                          collect (orrery/coalton/core:cl-make-usage-entry "gpt-4" (* i 100) (* i 50) i)))
           (rec (orrery/coalton/core:cl-recommend-model
                 profiles entries (orrery/coalton/core:cl-opt-balanced))))
      (formatting-row (pane)
        (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-rr-model rec)))
        (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-rr-strategy-label rec)))
        (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-rr-confidence-label rec)))
        (formatting-cell (pane) (format pane "~D" (orrery/coalton/core:cl-rr-savings-pct rec)))))))

;;; ─── Capacity Planner Pane ───

(defun display-capacity-planner (frame pane)
  "Display capacity plan with zone assessments."
  (declare (ignore frame) (optimize (safety 3)))
  (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
         (values (list 150 30000 3000 60))
         (plan (orrery/coalton/core:cl-build-capacity-plan thresholds values)))
    (format pane "Overall: ~A (headroom: ~D%)~%~%"
            (orrery/coalton/core:cl-plan-worst-zone-label plan)
            (orrery/coalton/core:cl-plan-headroom-pct plan))
    (formatting-table (pane)
      (formatting-row (pane)
        (formatting-cell (pane) (format pane "Metric"))
        (formatting-cell (pane) (format pane "Value"))
        (formatting-cell (pane) (format pane "Zone"))
        (formatting-cell (pane) (format pane "Headroom"))
        (formatting-cell (pane) (format pane "Util %")))
      (dolist (a (orrery/coalton/core:cl-plan-assessments plan))
        (formatting-row (pane)
          (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-assess-metric-name a)))
          (formatting-cell (pane) (format pane "~D" (orrery/coalton/core:cl-assess-value a)))
          (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-assess-zone-label a)))
          (formatting-cell (pane) (format pane "~D" (orrery/coalton/core:cl-assess-headroom a)))
          (formatting-cell (pane) (format pane "~D" (orrery/coalton/core:cl-assess-util-pct a))))))))

;;; ─── Session Analytics Pane ───

(defun display-session-analytics (frame pane)
  "Display session analytics summary."
  (declare (ignore frame) (optimize (safety 3)))
  (let* ((metrics (loop for i from 1 to 5
                        collect (orrery/coalton/core:cl-make-session-metric
                                 (format nil "sess-~D" i)
                                 (* i 120) (* i 2000) (* i 20) (* i 100)
                                 (nth (mod i 3) '("gpt-4" "claude-3" "llama-70b")))))
         (summary (orrery/coalton/core:cl-analyze-sessions metrics)))
    (format pane "Sessions: ~D | Avg Duration: ~Ds | Avg Tokens/Msg: ~D | Total Cost: ~D¢~%~%"
            (orrery/coalton/core:cl-sas-total summary)
            (orrery/coalton/core:cl-sas-avg-duration summary)
            (orrery/coalton/core:cl-sas-avg-tokens-per-msg summary)
            (orrery/coalton/core:cl-sas-total-cost summary))
    ;; Duration distribution
    (format pane "Duration Distribution:~%")
    (formatting-table (pane)
      (formatting-row (pane)
        (formatting-cell (pane) (format pane "Bucket"))
        (formatting-cell (pane) (format pane "Count")))
      (dolist (b (orrery/coalton/core:cl-sas-duration-buckets summary))
        (formatting-row (pane)
          (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-db-label b)))
          (formatting-cell (pane) (format pane "~D" (orrery/coalton/core:cl-db-count b))))))))

;;; ─── Audit Trail Pane ───

(defun display-audit-trail (frame pane)
  "Display audit trail entries."
  (declare (ignore frame) (optimize (safety 3)))
  ;; Build sample audit entries
  (let* ((hash-fn (lambda (s) (format nil "h-~A" s)))
         (trail (orrery/coalton/core:cl-empty-trail))
         (entries (list
                   (orrery/coalton/core:cl-make-single-entry
                    hash-fn trail
                    1000 (orrery/coalton/core:cl-audit-session-lifecycle)
                    (orrery/coalton/core:cl-audit-info)
                    "system" "Session started" "agent-1 via telegram")
                   (orrery/coalton/core:cl-make-single-entry
                    hash-fn trail
                    2000 (orrery/coalton/core:cl-audit-policy-change)
                    (orrery/coalton/core:cl-audit-warning)
                    "admin" "Budget policy updated" "Increased daily cap")
                   (orrery/coalton/core:cl-make-single-entry
                    hash-fn trail
                    3000 (orrery/coalton/core:cl-audit-alert-fired)
                    (orrery/coalton/core:cl-audit-critical)
                    "monitor" "Cost threshold exceeded" "Daily spend >$50"))))
    (formatting-table (pane)
      (formatting-row (pane)
        (formatting-cell (pane) (format pane "Seq"))
        (formatting-cell (pane) (format pane "Time"))
        (formatting-cell (pane) (format pane "Category"))
        (formatting-cell (pane) (format pane "Severity"))
        (formatting-cell (pane) (format pane "Actor"))
        (formatting-cell (pane) (format pane "Summary")))
      (dolist (e entries)
        (formatting-row (pane)
          (formatting-cell (pane) (format pane "~D" (orrery/coalton/core:cl-entry-seq e)))
          (formatting-cell (pane) (format pane "~D" (orrery/coalton/core:cl-entry-timestamp e)))
          (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-entry-category-label e)))
          (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-entry-severity-label e)))
          (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-entry-actor e)))
          (formatting-cell (pane) (format pane "~A" (orrery/coalton/core:cl-entry-summary e))))))))
