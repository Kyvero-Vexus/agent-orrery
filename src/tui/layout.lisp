;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; layout.lisp — Pure panel grid model and layout arithmetic
;;;
;;; Bead: agent-orrery-eb0.3.1
;;;
;;; All functions are pure — no terminal I/O. Given screen dimensions,
;;; compute panel positions and sizes for a 3×2 grid with status bar.

(in-package #:orrery/tui)

;;; ============================================================
;;; Panel struct
;;; ============================================================

(defstruct (panel (:conc-name panel-))
  "A renderable dashboard panel with grid position."
  (id        :sessions :type keyword)
  (title     ""        :type string)
  (visible-p t         :type boolean)
  (focused-p nil       :type boolean)
  (row       0         :type fixnum)
  (col       0         :type fixnum)
  (height    10        :type fixnum)
  (width     40        :type fixnum))

;;; ============================================================
;;; Layout struct
;;; ============================================================

(defstruct (layout (:conc-name layout-))
  "Dashboard panel grid state."
  (panels       '() :type list)
  (active-panel :sessions :type keyword)
  (screen-rows  24  :type fixnum)
  (screen-cols  80  :type fixnum)
  (status-line  ""  :type string))

;;; ============================================================
;;; Panel definitions (canonical order)
;;; ============================================================

(defparameter *panel-ids*
  '(:sessions :cron :health :events :alerts :usage)
  "Panel identifiers in display order.")

(defparameter *panel-titles*
  '((:sessions . "Sessions (1)")
    (:cron     . "Cron (2)")
    (:health   . "Health (3)")
    (:events   . "Events (4)")
    (:alerts   . "Alerts (5)")
    (:usage    . "Usage (6)"))
  "Display titles for each panel.")

;;; ============================================================
;;; Grid computation — pure arithmetic
;;; ============================================================

(declaim (ftype (function (fixnum fixnum) list) compute-grid))
(defun compute-grid (screen-rows screen-cols)
  "Compute panel list with positions for a 3-row × 2-column grid.
   Reserves 1 row at bottom for status bar.
   Returns list of panel structs with grid positions computed."
  (let* ((usable-rows (- screen-rows 1))  ; reserve status bar
         (row-height  (floor usable-rows 3))
         (col-width   (floor screen-cols 2))
         ;; Last row gets remainder height
         (last-row-h  (- usable-rows (* row-height 2)))
         ;; Right column gets remainder width
         (right-col-w (- screen-cols col-width)))
    ;; 3 rows × 2 cols: sessions/health, cron/events, alerts/usage
    (list
     (make-panel :id :sessions :title "Sessions (1)"
                 :row 0 :col 0
                 :height row-height :width col-width
                 :focused-p t)
     (make-panel :id :health :title "Health (3)"
                 :row 0 :col col-width
                 :height row-height :width right-col-w)
     (make-panel :id :cron :title "Cron (2)"
                 :row row-height :col 0
                 :height row-height :width col-width)
     (make-panel :id :events :title "Events (4)"
                 :row row-height :col col-width
                 :height row-height :width right-col-w)
     (make-panel :id :alerts :title "Alerts (5)"
                 :row (* row-height 2) :col 0
                 :height last-row-h :width col-width)
     (make-panel :id :usage :title "Usage (6)"
                 :row (* row-height 2) :col col-width
                 :height last-row-h :width right-col-w))))

(declaim (ftype (function (&key (:rows fixnum) (:cols fixnum)) layout)
                make-default-layout))
(defun make-default-layout (&key (rows 24) (cols 80))
  "Create a default dashboard layout for the given screen dimensions."
  (make-layout :panels (compute-grid rows cols)
               :active-panel :sessions
               :screen-rows rows
               :screen-cols cols))

;;; ============================================================
;;; Panel lookup and focus cycling
;;; ============================================================

(declaim (ftype (function (keyword layout) (or null panel)) find-panel))
(defun find-panel (id layout)
  "Find panel by ID in layout. Returns NIL if not found."
  (find id (layout-panels layout) :key #'panel-id))

(defparameter *cycle-order*
  '(:sessions :cron :health :events :alerts :usage)
  "Focus cycle order for Tab navigation.")

(declaim (ftype (function (layout &key (:reverse-p boolean)) layout) cycle-focus))
(defun cycle-focus (layout &key reverse-p)
  "Return new layout with focus moved to next (or previous) panel.
   Pure — returns a fresh layout, original unchanged."
  (let* ((current (layout-active-panel layout))
         (order (if reverse-p (reverse *cycle-order*) *cycle-order*))
         (pos (position current order))
         (next-id (if pos
                      (nth (mod (1+ pos) (length order)) order)
                      (first order)))
         (new-panels
           (mapcar (lambda (p)
                     (let ((copy (copy-panel p)))
                       (setf (panel-focused-p copy)
                             (eq (panel-id copy) next-id))
                       copy))
                   (layout-panels layout))))
    (let ((new-layout (copy-layout layout)))
      (setf (layout-panels new-layout) new-panels
            (layout-active-panel new-layout) next-id)
      new-layout)))
