;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; keys.lisp — Data-driven keymap for TUI dashboard
;;;
;;; Bead: agent-orrery-eb0.3.1
;;;
;;; Keymap is an alist of (key . action-keyword). Pure lookup, no I/O.

(in-package #:orrery/tui)

;;; ============================================================
;;; Default keymap
;;; ============================================================

(defparameter *default-keymap*
  '((:tab       . :cycle-panel)
    (:btab      . :cycle-panel-reverse)
    (#\q        . :quit)
    (#\:        . :command-mode)
    (#\?        . :help)
    (#\r        . :refresh)
    (#\j        . :scroll-down)
    (#\k        . :scroll-up)
    (#\1        . :focus-sessions)
    (#\2        . :focus-cron)
    (#\3        . :focus-health)
    (#\4        . :focus-events)
    (#\5        . :focus-alerts)
    (#\6        . :focus-usage)
    (#\Escape   . :normal-mode))
  "Default keybindings. Keys may be characters or keyword symbols.")

;;; ============================================================
;;; Keymap lookup
;;; ============================================================

(declaim (ftype (function (t &optional list) (or null keyword)) lookup-action))
(defun lookup-action (key &optional (keymap *default-keymap*))
  "Look up the action for KEY in KEYMAP. Returns NIL if unbound."
  (cdr (assoc key keymap :test #'equal)))
