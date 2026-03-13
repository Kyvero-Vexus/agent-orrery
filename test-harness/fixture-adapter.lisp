;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; fixture-adapter.lisp — Fixture adapter implementing adapter protocol
;;;

(in-package #:orrery/harness)

;;; ============================================================
;;; Fixture Adapter
;;; ============================================================

(defclass fixture-adapter ()
  ((clock     :initarg :clock     :reader fixture-adapter-clock)
   (timeline  :initarg :timeline  :reader fixture-adapter-timeline)
   (sessions  :initarg :sessions  :accessor fixture-sessions)
   (cron-jobs :initarg :cron-jobs :accessor fixture-cron-jobs)
   (health    :initarg :health    :accessor fixture-health)
   (usage     :initarg :usage     :accessor fixture-usage)
   (events    :initarg :events    :accessor fixture-events)
   (alerts    :initarg :alerts    :accessor fixture-alerts)
   (subagents :initarg :subagents :accessor fixture-subagents))
  (:documentation "A fixture adapter populated with deterministic test data."))

(declaim (ftype (function (&key (:clock (or null fixture-clock))) fixture-adapter)
                make-fixture-adapter))
(defun make-fixture-adapter (&key clock)
  "Create a fully populated fixture adapter with deterministic data."
  (let* ((clk (or clock (make-fixture-clock)))
         (tl (make-timeline)))
    (make-instance 'fixture-adapter
                   :clock clk
                   :timeline tl
                   :sessions (generate-sessions clk)
                   :cron-jobs (generate-cron-jobs clk)
                   :health (generate-health-checks clk)
                   :usage (generate-usage-records clk)
                   :events (generate-events clk)
                   :alerts (generate-alerts clk)
                   :subagents (generate-subagent-runs clk))))

;;; ============================================================
;;; Adapter protocol implementation
;;; ============================================================

(defmethod adapter-list-sessions ((adapter fixture-adapter))
  (fixture-sessions adapter))

(defmethod adapter-session-history ((adapter fixture-adapter) session-id)
  "Return synthetic message history for SESSION-ID."
  (let ((session (find session-id (fixture-sessions adapter)
                       :key #'sr-id :test #'string=)))
    (when session
      (loop for i from 1 to (min 5 (sr-message-count session))
            collect (list :role (if (oddp i) :user :assistant)
                          :content (format nil "Message ~D in ~A" i session-id)
                          :timestamp (+ (sr-created-at session) (* i 30)))))))

(defmethod adapter-list-cron-jobs ((adapter fixture-adapter))
  (fixture-cron-jobs adapter))

(defmethod adapter-trigger-cron ((adapter fixture-adapter) job-name)
  "Trigger a cron job: mark as running, increment run-count, schedule completion."
  (let ((job (find job-name (fixture-cron-jobs adapter)
                   :key #'cr-name :test #'string=)))
    (when job
      (let ((now (clock-now (fixture-adapter-clock adapter))))
        (setf (cr-status job) :active)
        (setf (cr-last-run-at job) now)
        (incf (cr-run-count job))
        ;; Schedule completion 10 seconds later
        (timeline-schedule
         (fixture-adapter-timeline adapter)
         (+ now 10)
         (lambda ()
           (setf (cr-status job) :active)
           (setf (cr-next-run-at job)
                 (+ (clock-now (fixture-adapter-clock adapter))
                    (cr-interval-s job)))))
        t))))

(defmethod adapter-system-health ((adapter fixture-adapter))
  (fixture-health adapter))

(defmethod adapter-usage-records ((adapter fixture-adapter) &key (period :hourly))
  (remove-if-not (lambda (r) (eq (ur-period r) period))
                 (fixture-usage adapter)))

(defmethod adapter-tail-events ((adapter fixture-adapter) &key (since 0) (limit 50))
  (let ((filtered (remove-if (lambda (e) (< (er-timestamp e) since))
                             (fixture-events adapter))))
    (subseq filtered 0 (min limit (length filtered)))))

(defmethod adapter-list-alerts ((adapter fixture-adapter))
  (fixture-alerts adapter))

(defmethod adapter-acknowledge-alert ((adapter fixture-adapter) alert-id)
  "Acknowledge an alert by flipping its acknowledged-p flag."
  (let ((alert (find alert-id (fixture-alerts adapter)
                     :key #'ar-id :test #'string=)))
    (when alert
      (setf (ar-acknowledged-p alert) t)
      t)))

(defmethod adapter-list-subagents ((adapter fixture-adapter))
  (fixture-subagents adapter))
