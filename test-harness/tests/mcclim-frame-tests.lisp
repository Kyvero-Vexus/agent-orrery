;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcclim-frame-tests.lisp — Tests for McCLIM frame/panes
;;; Bead: agent-orrery-eb0.5.1

(in-package #:orrery/harness-tests)

(define-test mcclim-frame-suite

  ;; Package exists
  (define-test mcclim-package-exists
    (true (find-package :orrery/mcclim)))

  ;; Frame class defined
  (define-test mcclim-frame-class
    (true (find-class 'orrery/mcclim:orrery-dashboard nil)))

  ;; Display functions exported
  (define-test mcclim-display-sessions-exported
    (true (fboundp 'orrery/mcclim:display-sessions)))

  (define-test mcclim-display-cron-exported
    (true (fboundp 'orrery/mcclim:display-cron)))

  (define-test mcclim-display-health-exported
    (true (fboundp 'orrery/mcclim:display-health)))

  (define-test mcclim-display-events-exported
    (true (fboundp 'orrery/mcclim:display-events)))

  (define-test mcclim-display-alerts-exported
    (true (fboundp 'orrery/mcclim:display-alerts)))

  (define-test mcclim-display-status-exported
    (true (fboundp 'orrery/mcclim:display-status)))

  ;; Presentation types defined
  (define-test mcclim-presentation-session
    (true (find-symbol "SESSION-PRESENTATION" :orrery/mcclim)))

  (define-test mcclim-presentation-cron
    (true (find-symbol "CRON-PRESENTATION" :orrery/mcclim)))

  (define-test mcclim-presentation-health
    (true (find-symbol "HEALTH-PRESENTATION" :orrery/mcclim)))

  (define-test mcclim-presentation-alert
    (true (find-symbol "ALERT-PRESENTATION" :orrery/mcclim)))

  ;; Fixture data populated
  (define-test mcclim-fixture-sessions
    (true (= 3 (length orrery/mcclim:*fixture-sessions*))))

  (define-test mcclim-fixture-cron
    (true (= 3 (length orrery/mcclim:*fixture-cron*))))

  (define-test mcclim-fixture-health
    (true (= 3 (length orrery/mcclim:*fixture-health*))))

  (define-test mcclim-fixture-events
    (true (= 3 (length orrery/mcclim:*fixture-events*))))

  (define-test mcclim-fixture-alerts
    (true (= 2 (length orrery/mcclim:*fixture-alerts*)))))
