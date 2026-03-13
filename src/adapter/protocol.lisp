;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; protocol.lisp — Adapter protocol contract
;;;
;;; Defines the generic function interface that all adapters must implement.
;;; Also defines adapter condition types for error reporting.
;;;
;;; An adapter is any CLOS instance that specializes these generics.
;;; See orrery/harness:fixture-adapter for the reference implementation.

(in-package #:orrery/adapter)

;;; ============================================================
;;; Condition types
;;; ============================================================

(define-condition adapter-error (error)
  ((adapter   :initarg :adapter   :reader adapter-error-adapter)
   (operation :initarg :operation :reader adapter-error-operation
              :type keyword))
  (:report (lambda (c s)
             (format s "Adapter error in ~A: ~A"
                     (adapter-error-operation c)
                     (adapter-error-adapter c))))
  (:documentation "Base condition for adapter protocol errors."))

(define-condition adapter-not-supported (adapter-error)
  ()
  (:report (lambda (c s)
             (format s "Operation ~A not supported by adapter ~A"
                     (adapter-error-operation c)
                     (type-of (adapter-error-adapter c)))))
  (:documentation "Signaled when an adapter does not support a requested operation.
Use ADAPTER-CAPABILITIES to check before calling."))

(define-condition adapter-not-found (adapter-error)
  ((id :initarg :id :reader adapter-not-found-id :type string))
  (:report (lambda (c s)
             (format s "~A not found: ~A"
                     (adapter-error-operation c)
                     (adapter-not-found-id c))))
  (:documentation "Signaled when a referenced entity (session, job, alert) does not exist."))

;;; ============================================================
;;; Query protocol — read-only operations
;;; ============================================================

(defgeneric adapter-list-sessions (adapter)
  (:documentation "Return a list of SESSION-RECORD representing all known sessions.
Results are ordered by CREATED-AT descending (most recent first) when possible."))

(defgeneric adapter-session-history (adapter session-id)
  (:documentation "Return message history for SESSION-ID as a list of HISTORY-ENTRY.
SESSION-ID is a string matching SR-ID. Returns NIL if session not found.
Results are ordered by HE-TIMESTAMP ascending (chronological)."))

(defgeneric adapter-list-cron-jobs (adapter)
  (:documentation "Return a list of CRON-RECORD for all registered cron jobs."))

(defgeneric adapter-system-health (adapter)
  (:documentation "Return a list of HEALTH-RECORD, one per monitored component.
Standard components: \"gateway\", \"sbcl\", \"adapter\"."))

(defgeneric adapter-usage-records (adapter &key period)
  (:documentation "Return a list of USAGE-RECORD filtered by PERIOD.
PERIOD is a keyword: :HOURLY (default) or :DAILY."))

(defgeneric adapter-tail-events (adapter &key since limit)
  (:documentation "Return recent EVENT-RECORDs.
SINCE: universal-time lower bound (default 0 = all).
LIMIT: maximum number of records (default 50).
Results are ordered by ER-TIMESTAMP ascending."))

(defgeneric adapter-list-alerts (adapter)
  (:documentation "Return a list of ALERT-RECORD for all active alerts."))

(defgeneric adapter-list-subagents (adapter)
  (:documentation "Return a list of SUBAGENT-RECORD for all known sub-agent runs."))

;;; ============================================================
;;; Command protocol — mutating operations
;;; ============================================================

(defgeneric adapter-trigger-cron (adapter job-name)
  (:documentation "Trigger an immediate run of cron job JOB-NAME (string).
Returns T on success. Signals ADAPTER-NOT-FOUND if job doesn't exist."))

(defgeneric adapter-pause-cron (adapter job-name)
  (:documentation "Pause cron job JOB-NAME so it does not fire on schedule.
Returns T on success. Signals ADAPTER-NOT-FOUND if job doesn't exist.
Signals ADAPTER-NOT-SUPPORTED if the adapter cannot pause jobs."))

(defgeneric adapter-resume-cron (adapter job-name)
  (:documentation "Resume a previously paused cron job JOB-NAME.
Returns T on success. Signals ADAPTER-NOT-FOUND if job doesn't exist.
Signals ADAPTER-NOT-SUPPORTED if the adapter cannot resume jobs."))

(defgeneric adapter-acknowledge-alert (adapter alert-id)
  (:documentation "Acknowledge alert ALERT-ID (string matching AR-ID).
Returns T on success. Signals ADAPTER-NOT-FOUND if alert doesn't exist."))

(defgeneric adapter-snooze-alert (adapter alert-id duration-seconds)
  (:documentation "Snooze alert ALERT-ID for DURATION-SECONDS.
Sets AR-SNOOZED-UNTIL to (+ current-time duration-seconds).
Returns T on success. Signals ADAPTER-NOT-FOUND if alert doesn't exist."))

;;; ============================================================
;;; Capability introspection
;;; ============================================================

(defgeneric adapter-capabilities (adapter)
  (:documentation "Return a list of ADAPTER-CAPABILITY describing supported operations.
Each capability has a name (string), description, and supported-p flag.
UI layers should check this before enabling command buttons/keys.

Standard capability names:
  \"trigger-cron\"       — can trigger manual cron runs
  \"pause-cron\"         — can pause/resume cron jobs
  \"acknowledge-alert\"  — can acknowledge alerts
  \"snooze-alert\"       — can snooze alerts
  \"session-history\"    — can retrieve session message history"))
