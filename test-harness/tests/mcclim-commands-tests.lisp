;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcclim-commands-tests.lisp — Tests for McCLIM command tables
;;; Bead: agent-orrery-eb0.5.2

(in-package #:orrery/harness-tests)

(define-test mcclim-commands-suite

  ;; Session commands
  (define-test mcclim-cmd-inspect-session
    (true (fboundp 'orrery/mcclim:com-inspect-session)))

  (define-test mcclim-cmd-list-sessions
    (true (fboundp 'orrery/mcclim:com-list-sessions)))

  ;; Cron commands
  (define-test mcclim-cmd-inspect-cron
    (true (fboundp 'orrery/mcclim:com-inspect-cron)))

  (define-test mcclim-cmd-trigger-cron
    (true (fboundp 'orrery/mcclim:com-trigger-cron)))

  (define-test mcclim-cmd-pause-cron
    (true (fboundp 'orrery/mcclim:com-pause-cron)))

  (define-test mcclim-cmd-resume-cron
    (true (fboundp 'orrery/mcclim:com-resume-cron)))

  (define-test mcclim-cmd-list-cron
    (true (fboundp 'orrery/mcclim:com-list-cron)))

  ;; Health command
  (define-test mcclim-cmd-inspect-health
    (true (fboundp 'orrery/mcclim:com-inspect-health)))

  ;; Alert commands
  (define-test mcclim-cmd-inspect-alert
    (true (fboundp 'orrery/mcclim:com-inspect-alert)))

  (define-test mcclim-cmd-list-alerts
    (true (fboundp 'orrery/mcclim:com-list-alerts)))

  ;; Dashboard commands
  (define-test mcclim-cmd-refresh
    (true (fboundp 'orrery/mcclim:com-refresh)))

  (define-test mcclim-cmd-status
    (true (fboundp 'orrery/mcclim:com-status)))

  ;; Command table exists on frame
  (define-test mcclim-command-table-exists
    (true (find-class 'orrery/mcclim:orrery-dashboard nil))))
