;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; state.lisp — TUI application state + pure action dispatch
;;;
;;; Bead: agent-orrery-eb0.3.1
;;;
;;; tui-state holds everything the TUI needs. dispatch-action is a pure
;;; state transition function: (tui-state × action) → tui-state.

(in-package #:orrery/tui)

;;; ============================================================
;;; Application state
;;; ============================================================

(defstruct (tui-state (:conc-name ts-))
  "Full TUI application state — pure, replaceable."
  (layout        nil :type (or null layout))
  (store         nil)  ; sync-store or nil
  (now             0 :type fixnum)
  (mode       :normal :type keyword)    ; :normal :command :help
  (command-input  "" :type string)
  (message        "" :type string)
  (running-p       t :type boolean))

;;; ============================================================
;;; Focus-to-panel mapping
;;; ============================================================

(defparameter *focus-action-map*
  '((:focus-sessions . :sessions)
    (:focus-cron     . :cron)
    (:focus-health   . :health)
    (:focus-events   . :events)
    (:focus-alerts   . :alerts)
    (:focus-usage    . :usage))
  "Maps focus actions to panel IDs.")

;;; ============================================================
;;; Pure action dispatch
;;; ============================================================

(declaim (ftype (function (tui-state keyword) tui-state) dispatch-action))
(defun dispatch-action (state action)
  "Apply ACTION to STATE, returning a new tui-state. Pure function."
  (let ((new-state (copy-tui-state state)))
    (case action
      (:quit
       (setf (ts-running-p new-state) nil
             (ts-message new-state) "Quitting..."))
      (:cycle-panel
       (setf (ts-layout new-state)
             (cycle-focus (ts-layout state))
             (ts-message new-state) ""))
      (:cycle-panel-reverse
       (setf (ts-layout new-state)
             (cycle-focus (ts-layout state) :reverse-p t)
             (ts-message new-state) ""))
      (:command-mode
       (setf (ts-mode new-state) :command
             (ts-command-input new-state) ""
             (ts-message new-state) ""))
      (:normal-mode
       (setf (ts-mode new-state) :normal
             (ts-command-input new-state) ""
             (ts-message new-state) ""))
      (:help
       (setf (ts-mode new-state) :help
             (ts-message new-state) "Press ? again or Esc to exit help"))
      (:refresh
       (setf (ts-message new-state) "Refreshed"))
      (:scroll-down
       (setf (ts-message new-state) "↓"))
      (:scroll-up
       (setf (ts-message new-state) "↑"))
      (otherwise
       ;; Check focus-action-map for direct panel focus
       (let ((panel-id (cdr (assoc action *focus-action-map*))))
         (if panel-id
             (let* ((lay (ts-layout state))
                    (new-panels
                      (mapcar (lambda (p)
                                (let ((copy (copy-panel p)))
                                  (setf (panel-focused-p copy)
                                        (eq (panel-id copy) panel-id))
                                  copy))
                              (layout-panels lay)))
                    (new-layout (copy-layout lay)))
               (setf (layout-panels new-layout) new-panels
                     (layout-active-panel new-layout) panel-id
                     (ts-layout new-state) new-layout
                     (ts-message new-state)
                     (format nil "Focused: ~A" panel-id)))
             (setf (ts-message new-state)
                   (format nil "Unknown action: ~A" action))))))
    new-state))
