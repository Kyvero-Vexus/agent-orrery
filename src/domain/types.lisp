;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; types.lisp — Core domain types for Agent Orrery
;;;
;;; All types use defstruct with :conc-name for clean accessor names.
;;; All public constructor functions have (declaim ftype) declarations.

(in-package #:orrery/domain)

;;; ============================================================
;;; Session state
;;; ============================================================

(defstruct (session-record (:conc-name sr-))
  "Represents an active or historical agent session."
  (id                   "" :type string)
  (agent-name           "" :type string)
  (channel              "" :type string)
  (status           :active :type keyword)
  (model                "" :type string)
  (created-at            0 :type fixnum)
  (updated-at            0 :type fixnum)
  (message-count         0 :type fixnum)
  (total-tokens          0 :type fixnum)
  (estimated-cost-cents  0 :type fixnum))

;;; ============================================================
;;; Cron job state
;;; ============================================================

(defstruct (cron-record (:conc-name cr-))
  "Represents a scheduled cron job."
  (name         "" :type string)
  (kind   :periodic :type keyword)
  (interval-s    0 :type fixnum)
  (status   :active :type keyword)
  (last-run-at nil :type (or null fixnum))
  (next-run-at   0 :type fixnum)
  (run-count     0 :type fixnum)
  (last-error  nil :type (or null string))
  (description  "" :type string))

;;; ============================================================
;;; System health
;;; ============================================================

(defstruct (health-record (:conc-name hr-))
  "Represents a health check result for a system component."
  (component  "" :type string)
  (status    :ok :type keyword)
  (message    "" :type string)
  (checked-at  0 :type fixnum)
  (latency-ms  0 :type fixnum))

;;; ============================================================
;;; Token usage
;;; ============================================================

(defstruct (usage-record (:conc-name ur-))
  "Represents token usage for a model over a time period."
  (model                "" :type string)
  (period          :hourly :type keyword)
  (timestamp             0 :type fixnum)
  (prompt-tokens         0 :type fixnum)
  (completion-tokens     0 :type fixnum)
  (total-tokens          0 :type fixnum)
  (estimated-cost-cents  0 :type fixnum))

;;; ============================================================
;;; Event stream entry
;;; ============================================================

(defstruct (event-record (:conc-name er-))
  "Represents an event in the system event stream."
  (id        "" :type string)
  (kind   :info :type keyword)
  (source    "" :type string)
  (message   "" :type string)
  (timestamp  0 :type fixnum)
  (metadata nil))

;;; ============================================================
;;; Alert
;;; ============================================================

(defstruct (alert-record (:conc-name ar-))
  "Represents an alert fired by the monitoring system."
  (id               "" :type string)
  (severity    :warning :type keyword)
  (title            "" :type string)
  (message          "" :type string)
  (source           "" :type string)
  (fired-at          0 :type fixnum)
  (acknowledged-p  nil :type boolean)
  (snoozed-until   nil :type (or null fixnum)))

;;; ============================================================
;;; Audit trail entry (CL-side mirror of Coalton AuditEntry)
;;; ============================================================

(defstruct (audit-trail-entry (:conc-name ate-))
  "CL-side audit trail entry for web/TUI views."
  (seq          0 :type fixnum)
  (timestamp    0 :type fixnum)
  (category    "" :type string)
  (severity    "" :type string)
  (actor       "" :type string)
  (summary     "" :type string)
  (detail      "" :type string)
  (hash        "" :type string))

;;; ============================================================
;;; Session analytics summary (CL-side mirror of Coalton types)
;;; ============================================================

(defstruct (analytics-summary (:conc-name asm-))
  "CL-side aggregate session analytics for web/TUI views."
  (total-sessions    0 :type fixnum)
  (avg-duration-s    0 :type fixnum)
  (median-tokens     0 :type fixnum)
  (avg-tokens-per-msg 0 :type fixnum)
  (total-cost-cents  0 :type fixnum))

(defstruct (duration-bucket-record (:conc-name dbr-))
  "CL-side duration histogram bucket."
  (label "" :type string)
  (count  0 :type fixnum))

(defstruct (efficiency-record (:conc-name efr-))
  "CL-side per-session efficiency metrics."
  (session-id          "" :type string)
  (tokens-per-message   0 :type fixnum)
  (tokens-per-minute    0 :type fixnum)
  (cost-per-1k          0 :type fixnum))

;;; ============================================================
;;; Sub-agent run
;;; ============================================================

(defstruct (subagent-record (:conc-name sar-))
  "Represents a sub-agent spawned by a session."
  (id              "" :type string)
  (parent-session  "" :type string)
  (agent-name      "" :type string)
  (status     :running :type keyword)
  (started-at       0 :type fixnum)
  (finished-at    nil :type (or null fixnum))
  (total-tokens     0 :type fixnum)
  (result         nil :type (or null string)))

;;; ============================================================
;;; Message history entry
;;; ============================================================

(defstruct (history-entry (:conc-name he-))
  "A single message in session history."
  (role      :user :type keyword)
  (content      "" :type string)
  (timestamp     0 :type fixnum)
  (token-count   0 :type fixnum))

;;; ============================================================
;;; Adapter capability descriptor
;;; ============================================================

(defstruct (adapter-capability (:conc-name cap-))
  "Describes a command/operation an adapter supports."
  (name        "" :type string)
  (description "" :type string)
  (supported-p  t :type boolean))
