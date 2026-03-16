;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcclim-accessibility-tests.lisp — Accessibility + keyboard parity tests
;;; Bead: agent-orrery-eb0.5.4

(in-package #:orrery/harness-tests)

(define-test mcclim-accessibility-suite

  ;; Shortcut registry
  (define-test mcclim-shortcuts-non-empty
    (true (> (length orrery/mcclim:*keyboard-shortcuts*) 0)))

  (define-test mcclim-shortcut-help-present
    (true (assoc "?" orrery/mcclim:*keyboard-shortcuts* :test #'string=)))

  (define-test mcclim-shortcut-refresh-present
    (true (assoc "C-r" orrery/mcclim:*keyboard-shortcuts* :test #'string=)))

  (define-test mcclim-shortcut-quit-present
    (true (assoc "q" orrery/mcclim:*keyboard-shortcuts* :test #'string=)))

  ;; Focus order
  (define-test mcclim-focus-order-non-empty
    (true (> (length orrery/mcclim:*focus-order*) 0)))

  (define-test mcclim-focus-order-has-interactor
    (true (member "INTERACTOR"
                  (mapcar #'symbol-name orrery/mcclim:*focus-order*)
                  :test #'string=)))

  ;; Pure helper behavior
  (define-test wrap-index-in-range
    (is = 2 (orrery/mcclim:wrap-index 2 0 5)))

  (define-test wrap-index-underflow
    (is = 5 (orrery/mcclim:wrap-index -1 0 5)))

  (define-test wrap-index-overflow
    (is = 0 (orrery/mcclim:wrap-index 6 0 5)))

  ;; Command symbols exported
  (define-test mcclim-command-help
    (true (fboundp 'orrery/mcclim:com-help)))

  (define-test mcclim-command-next-pane
    (true (fboundp 'orrery/mcclim:com-next-pane)))

  (define-test mcclim-command-prev-pane
    (true (fboundp 'orrery/mcclim:com-prev-pane)))

  (define-test mcclim-command-quick-status
    (true (fboundp 'orrery/mcclim:com-quick-status)))

  (define-test mcclim-command-quit
    (true (fboundp 'orrery/mcclim:com-quit))))
