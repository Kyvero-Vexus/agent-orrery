;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; generators.lisp — Deterministic fixture data generators
;;;

(in-package #:orrery/harness)

;;; ============================================================
;;; Deterministic generators
;;; ============================================================
;;;
;;; All generators produce identical output given the same clock state.
;;; They read clock-now but do NOT mutate the clock.

(defvar *agent-names* #("alpha" "beta" "gamma" "delta" "epsilon"
                        "zeta" "eta" "theta" "iota" "kappa"))

(defvar *channels* #("telegram" "irc" "webchat" "discord" "slack"))

(defvar *models* #("gpt-4" "claude-3" "gpt-3.5-turbo" "claude-2" "llama-70b"))

(defvar *session-statuses* #(:active :active :active :idle :closed))

(defvar *event-kinds* #(:info :info :info :warning :error :action))

(defvar *event-sources* #("system" "session:001" "cron:backup" "session:002" "system"))

;;; ------------------------------------------------------------
;;; Sessions
;;; ------------------------------------------------------------

(declaim (ftype (function (fixture-clock &key (:count fixnum)) list) generate-sessions))
(defun generate-sessions (clock &key (count 5))
  "Generate COUNT session-records with deterministic names/states."
  (let ((now (clock-now clock)))
    (loop for i from 1 to count
          collect (make-session-record
                   :id (format nil "session-~3,'0D" i)
                   :agent-name (aref *agent-names* (mod (1- i) (length *agent-names*)))
                   :channel (aref *channels* (mod (1- i) (length *channels*)))
                   :status (aref *session-statuses* (mod (1- i) (length *session-statuses*)))
                   :model (aref *models* (mod (1- i) (length *models*)))
                   :created-at (- now (* i 3600))
                   :updated-at (- now (* i 60))
                   :message-count (* i 10)
                   :total-tokens (* i 1500)
                   :estimated-cost-cents (* i 3)))))

;;; ------------------------------------------------------------
;;; Cron Jobs
;;; ------------------------------------------------------------

(defvar *cron-descriptions* #("Backup session logs"
                               "Sync usage metrics"
                               "Prune old events"))

(declaim (ftype (function (fixture-clock &key (:count fixnum)) list) generate-cron-jobs))
(defun generate-cron-jobs (clock &key (count 3))
  "Generate COUNT cron-records."
  (let ((now (clock-now clock)))
    (loop for i from 1 to count
          collect (make-cron-record
                   :name (format nil "cron-~3,'0D" i)
                   :kind (if (evenp i) :once :periodic)
                   :interval-s (* i 300)
                   :status (cond ((= i 1) :active)
                                 ((= i 2) :paused)
                                 (t :active))
                   :last-run-at (- now (* i 600))
                   :next-run-at (+ now (* i 300))
                   :run-count (* i 5)
                   :last-error nil
                   :description (aref *cron-descriptions*
                                     (mod (1- i) (length *cron-descriptions*)))))))

;;; ------------------------------------------------------------
;;; Health Checks
;;; ------------------------------------------------------------

(declaim (ftype (function (fixture-clock) list) generate-health-checks))
(defun generate-health-checks (clock)
  "Generate a standard set of health-records (gateway, sbcl, adapter)."
  (let ((now (clock-now clock)))
    (list
     (make-health-record :component "gateway"
                         :status :ok
                         :message "All systems nominal"
                         :checked-at now
                         :latency-ms 12)
     (make-health-record :component "sbcl"
                         :status :ok
                         :message "Heap usage normal"
                         :checked-at now
                         :latency-ms 3)
     (make-health-record :component "adapter"
                         :status :ok
                         :message "Connected"
                         :checked-at now
                         :latency-ms 45))))

;;; ------------------------------------------------------------
;;; Usage Records
;;; ------------------------------------------------------------

(declaim (ftype (function (fixture-clock &key (:models list) (:hours fixnum)) list)
                generate-usage-records))
(defun generate-usage-records (clock &key (models '("gpt-4" "claude-3")) (hours 24))
  "Generate hourly usage records for each model over HOURS hours."
  (let ((now (clock-now clock)))
    (loop for model in models
          for model-idx from 1
          append (loop for h from 0 below hours
                       for base-tokens = (* (+ 100 (* model-idx 50)) (1+ (mod h 7)))
                       for prompt = (floor (* base-tokens 6) 10)
                       for completion = (- base-tokens prompt)
                       collect (make-usage-record
                                :model model
                                :period :hourly
                                :timestamp (- now (* h 3600))
                                :prompt-tokens prompt
                                :completion-tokens completion
                                :total-tokens base-tokens
                                :estimated-cost-cents (floor base-tokens 100))))))

;;; ------------------------------------------------------------
;;; Events
;;; ------------------------------------------------------------

(declaim (ftype (function (fixture-clock &key (:count fixnum)) list) generate-events))
(defun generate-events (clock &key (count 20))
  "Generate COUNT event-records spanning the timeline."
  (let ((now (clock-now clock)))
    (loop for i from 1 to count
          collect (make-event-record
                   :id (format nil "evt-~3,'0D" i)
                   :kind (aref *event-kinds* (mod (1- i) (length *event-kinds*)))
                   :source (aref *event-sources* (mod (1- i) (length *event-sources*)))
                   :message (format nil "Event ~D occurred" i)
                   :timestamp (- now (* (- count i) 60))
                   :metadata (when (zerop (mod i 5))
                               (list :detail (format nil "extra-~D" i)))))))

;;; ------------------------------------------------------------
;;; Alerts
;;; ------------------------------------------------------------

(declaim (ftype (function (fixture-clock &key (:count fixnum)) list) generate-alerts))
(defun generate-alerts (clock &key (count 2))
  "Generate COUNT alert-records."
  (let ((now (clock-now clock)))
    (loop for i from 1 to count
          collect (make-alert-record
                   :id (format nil "alert-~3,'0D" i)
                   :severity (if (evenp i) :critical :warning)
                   :title (format nil "Alert ~D" i)
                   :message (format nil "Something needs attention (~D)" i)
                   :source (format nil "session:~3,'0D" i)
                   :fired-at (- now (* i 120))
                   :acknowledged-p nil
                   :snoozed-until nil))))

;;; ------------------------------------------------------------
;;; Subagent Runs
;;; ------------------------------------------------------------

(declaim (ftype (function (fixture-clock &key (:count fixnum)) list) generate-subagent-runs))
(defun generate-subagent-runs (clock &key (count 3))
  "Generate COUNT subagent-records."
  (let ((now (clock-now clock)))
    (loop for i from 1 to count
          collect (make-subagent-record
                   :id (format nil "sub-~3,'0D" i)
                   :parent-session (format nil "session-~3,'0D" (1+ (mod (1- i) 5)))
                   :agent-name (format nil "worker-~A"
                                       (aref *agent-names* (mod (1- i) (length *agent-names*))))
                   :status (cond ((= i 1) :running)
                                 ((= i 2) :completed)
                                 (t :running))
                   :started-at (- now (* i 180))
                   :finished-at (when (= i 2) (- now 60))
                   :total-tokens (* i 500)
                   :result (when (= i 2) "Task completed successfully")))))
