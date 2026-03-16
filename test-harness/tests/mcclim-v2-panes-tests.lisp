;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcclim-v2-panes-tests.lisp — Tests for McCLIM v2 pane functions
;;; Bead: agent-orrery-4qy
;;;
;;; McCLIM display functions require X11 for full rendering, but we can
;;; verify the Coalton bridge calls they depend on work correctly.

(in-package #:orrery/harness-tests)

(define-test mcclim-v2-panes-suite

  (define-test cost-optimizer-bridge-works
    "Verify the Coalton bridge used by display-cost-optimizer is functional."
    (let* ((profiles (list (orrery/coalton/core:cl-make-model-cost-profile "gpt-4" 30 60 900 300)
                           (orrery/coalton/core:cl-make-model-cost-profile "claude-3" 20 40 850 200)))
           (entries (loop for i from 1 to 20
                          collect (orrery/coalton/core:cl-make-usage-entry "gpt-4" (* i 100) (* i 50) i)))
           (rec (orrery/coalton/core:cl-recommend-model
                 profiles entries (orrery/coalton/core:cl-opt-balanced))))
      (true (stringp (orrery/coalton/core:cl-rr-model rec)))
      (true (stringp (orrery/coalton/core:cl-rr-strategy-label rec)))
      (true (stringp (orrery/coalton/core:cl-rr-confidence-label rec)))))

  (define-test capacity-planner-bridge-works
    "Verify the Coalton bridge used by display-capacity-planner is functional."
    (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
           (values (list 150 30000 3000 60))
           (plan (orrery/coalton/core:cl-build-capacity-plan thresholds values)))
      (true (stringp (orrery/coalton/core:cl-plan-worst-zone-label plan)))
      (true (integerp (orrery/coalton/core:cl-plan-headroom-pct plan)))
      (is = 4 (length (orrery/coalton/core:cl-plan-assessments plan)))))

  (define-test session-analytics-bridge-works
    "Verify the Coalton bridge used by display-session-analytics is functional."
    (let* ((metrics (loop for i from 1 to 5
                          collect (orrery/coalton/core:cl-make-session-metric
                                   (format nil "s-~D" i) (* i 120) (* i 2000) (* i 20) (* i 100) "gpt-4")))
           (summary (orrery/coalton/core:cl-analyze-sessions metrics)))
      (is = 5 (orrery/coalton/core:cl-sas-total summary))
      (is = 5 (length (orrery/coalton/core:cl-sas-duration-buckets summary)))))

  (define-test audit-trail-bridge-works
    "Verify the Coalton bridge used by display-audit-trail is functional."
    (let* ((trail (orrery/coalton/core:cl-empty-trail))
           (entry (orrery/coalton/core:cl-make-single-entry
                   (lambda (s) (format nil "hash-~A" s))
                   trail
                   1000 (orrery/coalton/core:cl-audit-session-lifecycle)
                   (orrery/coalton/core:cl-audit-info)
                   "system" "Test event" "Details")))
      (is = 1000 (orrery/coalton/core:cl-entry-timestamp entry))
      (true (stringp (orrery/coalton/core:cl-entry-category-label entry)))
      (true (stringp (orrery/coalton/core:cl-entry-severity-label entry)))))

  (define-test v2-display-functions-exist
    "Verify v2 display functions are defined."
    (true (fboundp 'orrery/mcclim:display-cost-optimizer))
    (true (fboundp 'orrery/mcclim:display-capacity-planner))
    (true (fboundp 'orrery/mcclim:display-session-analytics))
    (true (fboundp 'orrery/mcclim:display-audit-trail))))
