;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcclim-inspectors-tests.lisp — Tests for McCLIM inspectors
;;; Bead: agent-orrery-eb0.5.3

(in-package #:orrery/harness-tests)

(define-test mcclim-inspectors-suite

  ;; Inspector commands exist
  (define-test mcclim-insp-session-detail
    (true (fboundp 'orrery/mcclim:com-session-detail)))

  (define-test mcclim-insp-event-detail
    (true (fboundp 'orrery/mcclim:com-event-detail)))

  (define-test mcclim-insp-alert-detail
    (true (fboundp 'orrery/mcclim:com-alert-detail)))

  (define-test mcclim-insp-health-detail
    (true (fboundp 'orrery/mcclim:com-health-detail)))

  (define-test mcclim-insp-summary
    (true (fboundp 'orrery/mcclim:com-summary)))

  ;; Event presentation type
  (define-test mcclim-event-presentation-type
    (true (find-symbol "EVENT-PRESENTATION" :orrery/mcclim)))

  ;; Presentation methods defined (indirect — check class exists)
  (define-test mcclim-session-presentation-exists
    (true (find-symbol "SESSION-PRESENTATION" :orrery/mcclim)))

  (define-test mcclim-alert-presentation-exists
    (true (find-symbol "ALERT-PRESENTATION" :orrery/mcclim)))

  (define-test mcclim-health-presentation-exists
    (true (find-symbol "HEALTH-PRESENTATION" :orrery/mcclim))))
