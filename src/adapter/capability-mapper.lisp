;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capability-mapper.lisp — Typed command-capability mapper + safe executors
;;;
;;; Maps runtime adapter capabilities to allowed/denied operations with
;;; compile-time ftype contracts and typed command request/response envelopes.

(in-package #:orrery/adapter/openclaw)

;;; ─── Command request/response envelopes ───

(deftype command-kind ()
  '(member :trigger-cron :pause-cron :resume-cron
           :acknowledge-alert :snooze-alert
           :list-sessions :list-cron :system-health
           :usage-records :tail-events :list-alerts :list-subagents))

(defstruct (command-request
             (:constructor make-command-request (&key kind target-id params))
             (:conc-name cmd-req-))
  (kind :list-sessions :type command-kind)
  (target-id nil :type (or null string))
  (params nil :type list))

(defstruct (command-response
             (:constructor make-command-response (&key kind ok-p result error-detail))
             (:conc-name cmd-res-))
  (kind :list-sessions :type command-kind)
  (ok-p nil :type boolean)
  (result nil :type t)
  (error-detail nil :type (or null string)))

;;; ─── Capability gate ───

(defstruct (capability-gate
             (:constructor make-capability-gate (&key allowed-ops denied-ops))
             (:conc-name cg-))
  (allowed-ops '() :type list)
  (denied-ops '() :type list))

(define-condition operation-denied (error)
  ((operation :initarg :operation :reader operation-denied-op)
   (reason :initarg :reason :reader operation-denied-reason)))

(declaim (ftype (function (list) (values capability-gate &optional)) build-capability-gate)
         (ftype (function (capability-gate command-kind) (values boolean &optional)) operation-allowed-p)
         (ftype (function (capability-gate command-request) (values command-response &optional)) safe-execute))

;;; ─── Capability-to-operation mapping ───

(defparameter *capability-operation-map*
  '(("list-sessions"      . :list-sessions)
    ("session-history"     . :list-sessions)
    ("list-cron"           . :list-cron)
    ("trigger-cron"        . :trigger-cron)
    ("pause-cron"          . :pause-cron)
    ("resume-cron"         . :resume-cron)
    ("system-health"       . :system-health)
    ("usage-records"       . :usage-records)
    ("tail-events"         . :tail-events)
    ("list-alerts"         . :list-alerts)
    ("acknowledge-alert"   . :acknowledge-alert)
    ("snooze-alert"        . :snooze-alert)
    ("list-subagents"      . :list-subagents))
  "Maps adapter capability names to command-kind operations.")

(defun build-capability-gate (capabilities)
  "Build a capability gate from a list of adapter-capability structs.
   Supported capabilities become allowed-ops; all others are denied."
  (declare (type list capabilities))
  (let ((allowed '())
        (denied '())
        (all-ops '(:trigger-cron :pause-cron :resume-cron
                   :acknowledge-alert :snooze-alert
                   :list-sessions :list-cron :system-health
                   :usage-records :tail-events :list-alerts :list-subagents)))
    (dolist (cap capabilities)
      (let* ((name (orrery/domain:cap-name cap))
             (op (cdr (assoc name *capability-operation-map* :test #'string=))))
        (when (and op (orrery/domain:cap-supported-p cap))
          (pushnew op allowed))))
    (dolist (op all-ops)
      (unless (member op allowed)
        (push op denied)))
    (make-capability-gate :allowed-ops allowed :denied-ops denied)))

(defun operation-allowed-p (gate kind)
  "Check if an operation is permitted by the capability gate."
  (declare (type capability-gate gate) (type command-kind kind))
  (not (null (member kind (cg-allowed-ops gate)))))

(defun safe-execute (gate request)
  "Execute a command request only if capability gate allows it.
   Returns a command-response; denied operations get ok-p=nil with error-detail."
  (declare (type capability-gate gate) (type command-request request))
  (let ((kind (cmd-req-kind request)))
    (if (operation-allowed-p gate kind)
        (make-command-response :kind kind :ok-p t :result :executed)
        (make-command-response :kind kind :ok-p nil
                               :error-detail
                               (format nil "Operation ~A denied: not in adapter capabilities"
                                       kind)))))
