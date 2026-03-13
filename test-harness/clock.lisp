;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; clock.lisp — Deterministic fixture clock
;;;

(in-package #:orrery/harness)

;;; ============================================================
;;; Fixture Clock
;;; ============================================================

(defstruct (fixture-clock (:conc-name fc-)
                          (:constructor %make-fixture-clock))
  "A deterministic clock for test fixtures."
  (current-time 3920000000 :type fixnum))

(declaim (ftype (function (&key (:start-time fixnum)) fixture-clock) make-fixture-clock))
(defun make-fixture-clock (&key (start-time 3920000000))
  "Create a fixture clock starting at START-TIME (universal-time)."
  (%make-fixture-clock :current-time start-time))

(declaim (ftype (function (fixture-clock) fixnum) clock-now))
(defun clock-now (clock)
  "Return the current time of CLOCK."
  (fc-current-time clock))

(declaim (ftype (function (fixture-clock fixnum) fixnum) clock-advance!))
(defun clock-advance! (clock seconds)
  "Advance CLOCK by SECONDS. Returns the new time."
  (incf (fc-current-time clock) seconds))

(declaim (ftype (function (fixture-clock fixnum) fixnum) clock-set!))
(defun clock-set! (clock time)
  "Set CLOCK to absolute TIME. Returns TIME."
  (setf (fc-current-time clock) time))
