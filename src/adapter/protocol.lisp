;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; protocol.lisp — Adapter protocol (generic function contract)
;;;

(in-package #:orrery/adapter)

(defgeneric adapter-list-sessions (adapter)
  (:documentation "Return a list of SESSION-RECORD."))

(defgeneric adapter-session-history (adapter session-id)
  (:documentation "Return message history for SESSION-ID as a list of plists."))

(defgeneric adapter-list-cron-jobs (adapter)
  (:documentation "Return a list of CRON-RECORD."))

(defgeneric adapter-trigger-cron (adapter job-name)
  (:documentation "Trigger a cron job. Returns T on success."))

(defgeneric adapter-system-health (adapter)
  (:documentation "Return a list of HEALTH-RECORD."))

(defgeneric adapter-usage-records (adapter &key period)
  (:documentation "Return a list of USAGE-RECORD for PERIOD."))

(defgeneric adapter-tail-events (adapter &key since limit)
  (:documentation "Return recent EVENT-RECORDs since SINCE timestamp."))

(defgeneric adapter-list-alerts (adapter)
  (:documentation "Return a list of ALERT-RECORD."))

(defgeneric adapter-acknowledge-alert (adapter alert-id)
  (:documentation "Acknowledge an alert. Returns T on success."))

(defgeneric adapter-list-subagents (adapter)
  (:documentation "Return a list of SUBAGENT-RECORD."))
