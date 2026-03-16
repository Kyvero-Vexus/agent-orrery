;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-analytics-tests.lisp — Tests for TUI analytics cards
;;; Bead: agent-orrery-eb0.3.4

(in-package #:orrery/harness-tests)

(define-test tui-analytics-suite

  ;; ─── Time window ───

  (define-test time-window-cycle
    (is eq :day (orrery/tui:next-time-window :hour))
    (is eq :week (orrery/tui:next-time-window :day))
    (is eq :all (orrery/tui:next-time-window :week))
    (is eq :hour (orrery/tui:next-time-window :all)))

  (define-test time-window-labels
    (is string= "Last Hour" (orrery/tui:time-window-label :hour))
    (is string= "Last 24h" (orrery/tui:time-window-label :day))
    (is string= "Last 7d" (orrery/tui:time-window-label :week))
    (is string= "All Time" (orrery/tui:time-window-label :all)))

  ;; ─── Trend indicators ───

  (define-test trend-indicators
    (is string= "↑" (orrery/tui:trend-indicator :up))
    (is string= "↓" (orrery/tui:trend-indicator :down))
    (is string= "→" (orrery/tui:trend-indicator :flat)))

  ;; ─── Card building ───

  (define-test build-token-card
    (let* ((sessions (list (orrery/domain:make-session-record :total-tokens 5000)
                           (orrery/domain:make-session-record :total-tokens 3000)))
           (card (orrery/tui:build-token-usage-card sessions :hour)))
      (is string= "Total Tokens" (orrery/tui:ac-title card))
      (true (search "8" (orrery/tui:ac-value card)))
      (is eq :hour (orrery/tui:ac-window card))))

  (define-test build-cost-card
    (let* ((sessions (list (orrery/domain:make-session-record :estimated-cost-cents 250)
                           (orrery/domain:make-session-record :estimated-cost-cents 150)))
           (card (orrery/tui:build-cost-card sessions :day)))
      (is string= "Total Cost" (orrery/tui:ac-title card))
      (true (search "4" (orrery/tui:ac-value card)))
      (is eq :day (orrery/tui:ac-window card))))

  (define-test build-model-card
    (let* ((sessions (list (orrery/domain:make-session-record :model "claude")
                           (orrery/domain:make-session-record :model "gpt-4")
                           (orrery/domain:make-session-record :model "claude")))
           (card (orrery/tui:build-model-distribution-card sessions :week)))
      (is string= "Models Active" (orrery/tui:ac-title card))
      (true (search "2" (orrery/tui:ac-value card)))))

  (define-test build-session-count-card
    (let* ((sessions (list (orrery/domain:make-session-record :status :active)
                           (orrery/domain:make-session-record :status :idle)
                           (orrery/domain:make-session-record :status :active)))
           (card (orrery/tui:build-session-count-card sessions :all)))
      (is string= "Sessions" (orrery/tui:ac-title card))
      (true (search "2/3" (orrery/tui:ac-value card)))))

  ;; ─── State ───

  (define-test build-analytics-state-6-cards
    (let* ((sessions (list (orrery/domain:make-session-record :total-tokens 1000
                                                              :estimated-cost-cents 30
                                                              :model "claude"
                                                              :status :active)))
           (state (orrery/tui:build-analytics-state sessions :hour)))
      (is = 6 (length (orrery/tui:as-cards state)))
      (is eq :hour (orrery/tui:as-window state))))

  (define-test cycle-window-updates-all-cards
    (let* ((sessions (list (orrery/domain:make-session-record)))
           (state (orrery/tui:build-analytics-state sessions :hour))
           (cycled (orrery/tui:cycle-analytics-window state)))
      (is eq :day (orrery/tui:as-window cycled))
      (is eq :day (orrery/tui:ac-window (first (orrery/tui:as-cards cycled))))))

  ;; ─── Render ───

  (define-test render-analytics-lines-non-empty
    (let* ((sessions (list (orrery/domain:make-session-record)))
           (state (orrery/tui:build-analytics-state sessions :hour))
           (lines (orrery/tui:render-analytics-lines state)))
      (true (> (length lines) 4))
      (true (search "Analytics" (first lines)))))

  (define-test render-card-line-format
    (let ((card (orrery/tui:make-analytics-card
                 :title "Test" :value "42" :unit "items" :trend :up :window :hour)))
      (let ((line (orrery/tui:render-card-line card)))
        (true (search "Test" line))
        (true (search "42" line))
        (true (search "↑" line))))))
