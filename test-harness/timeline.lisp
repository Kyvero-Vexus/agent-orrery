;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; timeline.lisp — Scripted timeline engine
;;;

(in-package #:orrery/harness)

;;; ============================================================
;;; Timeline
;;; ============================================================

(defstruct (timeline (:conc-name tl-)
                     (:constructor %make-timeline))
  "A timeline of scheduled thunks, sorted by time."
  (entries nil :type list))

(declaim (ftype (function () timeline) make-timeline))
(defun make-timeline ()
  "Create an empty timeline."
  (%make-timeline :entries nil))

(declaim (ftype (function (timeline fixnum function) t) timeline-schedule))
(defun timeline-schedule (timeline time thunk)
  "Schedule THUNK to execute at TIME on TIMELINE."
  (let ((entry (cons time thunk)))
    (setf (tl-entries timeline)
          (merge 'list (list entry) (tl-entries timeline)
                 #'< :key #'car)))
  (values))

(declaim (ftype (function (timeline fixture-clock fixnum) fixnum) timeline-run-until!))
(defun timeline-run-until! (timeline clock target-time)
  "Advance CLOCK to TARGET-TIME, executing scheduled thunks in order.
Returns the number of thunks executed."
  (let ((executed 0))
    (declare (type fixnum executed))
    (loop
      (let ((entries (tl-entries timeline)))
        (when (or (null entries)
                  (> (the fixnum (caar entries)) target-time))
          (return))
        ;; Pop the entry
        (let ((entry (pop (tl-entries timeline))))
          (clock-set! clock (the fixnum (car entry)))
          (funcall (the function (cdr entry)))
          (incf executed))))
    ;; Advance clock to target even if no thunks fired
    (clock-set! clock target-time)
    executed))

(declaim (ftype (function (timeline) fixnum) timeline-pending-count))
(defun timeline-pending-count (timeline)
  "Return the number of pending thunks in TIMELINE."
  (length (tl-entries timeline)))
