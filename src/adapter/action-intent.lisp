;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; action-intent.lisp — Typed action-intent algebra for operator commands
;;;
;;; Defines a statically typed ADT for all operator intents (queries + commands)
;;; with pure interpreters per UI adapter boundary.  Removes duplicated
;;; imperative UI logic across TUI/Web/McCLIM surfaces.

(in-package #:orrery/adapter)

;;; ─── Intent Kind Type ───

(deftype intent-kind ()
  "Top-level intent discriminator."
  '(member
    ;; Query intents
    :list-sessions :session-history :list-cron-jobs :system-health
    :usage-records :tail-events :list-alerts :list-subagents :capabilities
    ;; Command intents
    :trigger-cron :pause-cron :resume-cron
    :acknowledge-alert :snooze-alert))

(deftype intent-category ()
  "Broad classification of intents for routing/display."
  '(member :query :command))

;;; ─── Action Intent ───

(defstruct (action-intent
             (:constructor make-action-intent
                 (&key kind target-id params))
             (:conc-name ai-))
  "One typed operator intent — a command or query request.
   Pure value: no side effects, no adapter references."
  (kind :list-sessions :type intent-kind)
  (target-id nil :type (or string null))
  (params nil :type list))

(declaim (ftype (function (action-intent) (values intent-category &optional))
                intent-category))
(defun intent-category (intent)
  "Classify an intent as :query or :command.  Pure."
  (declare (optimize (speed 3) (safety 3)))
  (ecase (ai-kind intent)
    ((:list-sessions :session-history :list-cron-jobs :system-health
      :usage-records :tail-events :list-alerts :list-subagents :capabilities)
     :query)
    ((:trigger-cron :pause-cron :resume-cron
      :acknowledge-alert :snooze-alert)
     :command)))

;;; ─── Intent Result ───

(deftype result-status ()
  "Outcome of executing an intent."
  '(member :ok :error :not-supported :not-found))

(defstruct (intent-result
             (:constructor make-intent-result
                 (&key status payload error-message intent))
             (:conc-name ir-))
  "Result of interpreting one action-intent against an adapter."
  (status :ok :type result-status)
  (payload nil :type t)
  (error-message "" :type string)
  (intent nil :type (or action-intent null)))

;;; ─── Convenience Intent Constructors ───

(declaim (ftype (function () (values action-intent &optional))
                intent-list-sessions intent-list-cron-jobs
                intent-system-health intent-list-alerts
                intent-list-subagents intent-capabilities))

(defun intent-list-sessions ()
  (make-action-intent :kind :list-sessions))

(defun intent-list-cron-jobs ()
  (make-action-intent :kind :list-cron-jobs))

(defun intent-system-health ()
  (make-action-intent :kind :system-health))

(defun intent-list-alerts ()
  (make-action-intent :kind :list-alerts))

(defun intent-list-subagents ()
  (make-action-intent :kind :list-subagents))

(defun intent-capabilities ()
  (make-action-intent :kind :capabilities))

(declaim (ftype (function (string) (values action-intent &optional))
                intent-session-history intent-trigger-cron
                intent-pause-cron intent-resume-cron
                intent-acknowledge-alert))

(defun intent-session-history (session-id)
  (declare (type string session-id))
  (make-action-intent :kind :session-history :target-id session-id))

(defun intent-trigger-cron (job-name)
  (declare (type string job-name))
  (make-action-intent :kind :trigger-cron :target-id job-name))

(defun intent-pause-cron (job-name)
  (declare (type string job-name))
  (make-action-intent :kind :pause-cron :target-id job-name))

(defun intent-resume-cron (job-name)
  (declare (type string job-name))
  (make-action-intent :kind :resume-cron :target-id job-name))

(defun intent-acknowledge-alert (alert-id)
  (declare (type string alert-id))
  (make-action-intent :kind :acknowledge-alert :target-id alert-id))

(declaim (ftype (function (string (integer 0)) (values action-intent &optional))
                intent-snooze-alert))
(defun intent-snooze-alert (alert-id duration-seconds)
  (declare (type string alert-id)
           (type (integer 0) duration-seconds))
  (make-action-intent :kind :snooze-alert :target-id alert-id
                      :params (list :duration-seconds duration-seconds)))

(declaim (ftype (function (&key (:period (or string null))) (values action-intent &optional))
                intent-usage-records))
(defun intent-usage-records (&key period)
  (make-action-intent :kind :usage-records
                      :params (when period (list :period period))))

(declaim (ftype (function (&key (:since (or integer null))
                                (:limit (or integer null)))
                          (values action-intent &optional))
                intent-tail-events))
(defun intent-tail-events (&key since limit)
  (make-action-intent :kind :tail-events
                      :params (append (when since (list :since since))
                                      (when limit (list :limit limit)))))

;;; ─── Pure Interpreter ───

(declaim (ftype (function (t action-intent) (values intent-result &optional))
                interpret-intent))
(defun interpret-intent (adapter intent)
  "Interpret one action-intent against ADAPTER.  Returns intent-result.
   Catches adapter-error conditions and wraps them as error results."
  (declare (optimize (safety 3)))
  (handler-case
      (let ((payload
              (ecase (ai-kind intent)
                (:list-sessions     (adapter-list-sessions adapter))
                (:session-history   (adapter-session-history adapter (ai-target-id intent)))
                (:list-cron-jobs    (adapter-list-cron-jobs adapter))
                (:system-health     (adapter-system-health adapter))
                (:usage-records     (apply #'adapter-usage-records adapter (ai-params intent)))
                (:tail-events       (apply #'adapter-tail-events adapter (ai-params intent)))
                (:list-alerts       (adapter-list-alerts adapter))
                (:list-subagents    (adapter-list-subagents adapter))
                (:capabilities      (adapter-capabilities adapter))
                (:trigger-cron      (adapter-trigger-cron adapter (ai-target-id intent)))
                (:pause-cron        (adapter-pause-cron adapter (ai-target-id intent)))
                (:resume-cron       (adapter-resume-cron adapter (ai-target-id intent)))
                (:acknowledge-alert (adapter-acknowledge-alert adapter (ai-target-id intent)))
                (:snooze-alert      (adapter-snooze-alert
                                     adapter (ai-target-id intent)
                                     (getf (ai-params intent) :duration-seconds 3600))))))
        (make-intent-result :status :ok :payload payload :intent intent))
    (adapter-not-supported (c)
      (make-intent-result :status :not-supported
                          :error-message (princ-to-string c)
                          :intent intent))
    (adapter-not-found (c)
      (make-intent-result :status :not-found
                          :error-message (princ-to-string c)
                          :intent intent))
    (adapter-error (c)
      (make-intent-result :status :error
                          :error-message (princ-to-string c)
                          :intent intent))))

;;; ─── Batch Interpreter ───

(declaim (ftype (function (t list) (values list &optional))
                interpret-intents))
(defun interpret-intents (adapter intents)
  "Interpret a list of action-intents, returning a list of intent-results.
   Preserves order correspondence.  Pure (no mutation of INTENTS)."
  (declare (optimize (safety 3)))
  (mapcar (lambda (intent) (interpret-intent adapter intent)) intents))

;;; ─── Intent Description (for UI display) ───

(declaim (ftype (function (action-intent) (values string &optional))
                describe-intent))
(defun describe-intent (intent)
  "Human-readable one-line description of an intent.  Pure."
  (declare (optimize (safety 3)))
  (let ((kind (ai-kind intent))
        (target (ai-target-id intent)))
    (case kind
      (:list-sessions     "List active sessions")
      (:session-history   (format nil "Show history for session ~A" target))
      (:list-cron-jobs    "List cron jobs")
      (:system-health     "Check system health")
      (:usage-records     "Fetch usage records")
      (:tail-events       "Tail recent events")
      (:list-alerts       "List active alerts")
      (:list-subagents    "List subagent runs")
      (:capabilities      "Query adapter capabilities")
      (:trigger-cron      (format nil "Trigger cron job ~A" target))
      (:pause-cron        (format nil "Pause cron job ~A" target))
      (:resume-cron       (format nil "Resume cron job ~A" target))
      (:acknowledge-alert (format nil "Acknowledge alert ~A" target))
      (:snooze-alert      (format nil "Snooze alert ~A" target))
      (otherwise          (format nil "Unknown intent ~A" kind)))))
