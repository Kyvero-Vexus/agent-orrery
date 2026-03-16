;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-cost-capacity-cards-tests.lisp — Tests for cost optimizer and capacity planner TUI cards
;;; Bead: agent-orrery-30m

(in-package #:orrery/harness-tests)

(define-test tui-cost-capacity-cards-suite

  ;; ─── Cost optimizer card ───

  (define-test cost-opt-card-no-data
    (let ((card (orrery/tui:build-cost-optimizer-card nil nil :hour)))
      (is string= "Cost Optimizer" (orrery/tui:ac-title card))
      (is string= "No data" (orrery/tui:ac-value card))))

  (define-test cost-opt-card-with-data
    (let* ((profiles (list (orrery/coalton/core:cl-make-model-cost-profile "gpt-4" 30 60 900 300)
                           (orrery/coalton/core:cl-make-model-cost-profile "claude" 20 40 850 200)))
           (entries (loop for i from 1 to 50
                          collect (orrery/coalton/core:cl-make-usage-entry "gpt-4" (* i 100) (* i 50) i)))
           (card (orrery/tui:build-cost-optimizer-card profiles entries :day)))
      (is string= "Cost Optimizer" (orrery/tui:ac-title card))
      (true (search "recommended" (orrery/tui:ac-unit card)))
      (false (string= "No data" (orrery/tui:ac-value card)))))

  (define-test cost-opt-card-window
    (let* ((profiles (list (orrery/coalton/core:cl-make-model-cost-profile "m" 10 20 700 300)))
           (entries (list (orrery/coalton/core:cl-make-usage-entry "m" 100 50 1)))
           (card (orrery/tui:build-cost-optimizer-card profiles entries :week)))
      (is eq :week (orrery/tui:ac-window card))))

  ;; ─── Capacity planner card ───

  (define-test capacity-card-no-data
    (let ((card (orrery/tui:build-capacity-planner-card nil nil :hour)))
      (is string= "Capacity" (orrery/tui:ac-title card))
      (is string= "No data" (orrery/tui:ac-value card))))

  (define-test capacity-card-normal
    (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
           (values (list 100 20000 2000 50))
           (card (orrery/tui:build-capacity-planner-card thresholds values :day)))
      (is string= "Capacity" (orrery/tui:ac-title card))
      (true (search "normal" (orrery/tui:ac-value card)))
      (true (search "headroom" (orrery/tui:ac-unit card)))))

  (define-test capacity-card-critical
    (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
           (values (list 900 90000 9000 250))
           (card (orrery/tui:build-capacity-planner-card thresholds values :hour)))
      (true (search "critical" (orrery/tui:ac-value card)))
      (is eq :down (orrery/tui:ac-trend card))))

  (define-test capacity-card-idle
    (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
           (values (list 10 1000 100 5))
           (card (orrery/tui:build-capacity-planner-card thresholds values :all)))
      (true (search "idle" (orrery/tui:ac-value card)))
      (is eq :flat (orrery/tui:ac-trend card))))

  (define-test render-card-line-works
    (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
           (values (list 100 20000 2000 50))
           (card (orrery/tui:build-capacity-planner-card thresholds values :day))
           (line (orrery/tui:render-card-line card)))
      (true (stringp line))
      (true (> (length line) 0)))))
