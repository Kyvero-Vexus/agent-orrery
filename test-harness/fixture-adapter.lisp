;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; fixture-adapter.lisp — Fixture adapter implementing full adapter protocol
;;;
;;; Reference implementation of the orrery/adapter contract.
;;; Uses deterministic generators and a controllable clock/timeline.

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
  (:documentation "A fixture adapter populated with deterministic test data.
Implements all orrery/adapter generics for use in E2E testing."))

(declaim (ftype (function (&key (:clock (or null fixture-clock))) fixture-adapter)
                make-fixture-adapter))
(defun make-fixture-adapter (&key clock)
  "Create a fully populated fixture adapter with deterministic data."
  (let* ((clk (or clock (make-fixture-clock)))
         (tl  (make-timeline)))
    (make-instance 'fixture-adapter
                   :clock     clk
                   :timeline  tl
                   :sessions  (generate-sessions clk)
                   :cron-jobs (generate-cron-jobs clk)
                   :health    (generate-health-checks clk)
                   :usage     (generate-usage-records clk)
                   :events    (generate-events clk)
                   :alerts    (generate-alerts clk)
                   :subagents (generate-subagent-runs clk))))

;;; ============================================================
;;; Internal helpers
;;; ============================================================

(defun %find-cron-job (adapter job-name)
  "Find a cron job by name or signal ADAPTER-NOT-FOUND."
  (or (find job-name (fixture-cron-jobs adapter)
            :key #'cr-name :test #'string=)
      (error 'adapter-not-found
             :adapter adapter :operation :cron :id job-name)))

(defun %find-alert (adapter alert-id)
  "Find an alert by ID or signal ADAPTER-NOT-FOUND."
  (or (find alert-id (fixture-alerts adapter)
            :key #'ar-id :test #'string=)
      (error 'adapter-not-found
             :adapter adapter :operation :alert :id alert-id)))

;;; ============================================================
;;; Query protocol implementation
;;; ============================================================

(defmethod adapter-list-sessions ((adapter fixture-adapter))
  (fixture-sessions adapter))

(defmethod adapter-session-history ((adapter fixture-adapter) session-id)
  "Return synthetic HISTORY-ENTRY list for SESSION-ID."
  (let ((session (find session-id (fixture-sessions adapter)
                       :key #'sr-id :test #'string=)))
    (when session
      (loop for i from 1 to (min 5 (sr-message-count session))
            collect (make-history-entry
                     :role (if (oddp i) :user :assistant)
                     :content (format nil "Message ~D in ~A" i session-id)
                     :timestamp (+ (sr-created-at session) (* i 30))
                     :token-count (* i 50))))))

(defmethod adapter-list-cron-jobs ((adapter fixture-adapter))
  (fixture-cron-jobs adapter))

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

(defmethod adapter-list-subagents ((adapter fixture-adapter))
  (fixture-subagents adapter))

;;; ============================================================
;;; Command protocol implementation
;;; ============================================================

(defmethod adapter-trigger-cron ((adapter fixture-adapter) job-name)
  "Trigger cron job: increment run-count, set last-run, schedule completion."
  (let* ((job (%find-cron-job adapter job-name))
         (now (clock-now (fixture-adapter-clock adapter))))
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
    t))

(defmethod adapter-pause-cron ((adapter fixture-adapter) job-name)
  "Pause a cron job by setting its status to :PAUSED."
  (let ((job (%find-cron-job adapter job-name)))
    (setf (cr-status job) :paused)
    t))

(defmethod adapter-resume-cron ((adapter fixture-adapter) job-name)
  "Resume a paused cron job by setting its status to :ACTIVE."
  (let ((job (%find-cron-job adapter job-name)))
    (setf (cr-status job) :active)
    t))

(defmethod adapter-acknowledge-alert ((adapter fixture-adapter) alert-id)
  "Acknowledge an alert by flipping its acknowledged-p flag."
  (let ((alert (%find-alert adapter alert-id)))
    (setf (ar-acknowledged-p alert) t)
    t))

(defmethod adapter-snooze-alert ((adapter fixture-adapter) alert-id duration-seconds)
  "Snooze an alert for DURATION-SECONDS."
  (let* ((alert (%find-alert adapter alert-id))
         (now   (clock-now (fixture-adapter-clock adapter))))
    (setf (ar-snoozed-until alert) (+ now duration-seconds))
    t))

;;; ============================================================
;;; Capability introspection
;;; ============================================================

(defmethod adapter-capabilities ((adapter fixture-adapter))
  "Fixture adapter supports all standard operations."
  (list
   (make-adapter-capability :name "trigger-cron"
                            :description "Trigger manual cron runs"
                            :supported-p t)
   (make-adapter-capability :name "pause-cron"
                            :description "Pause and resume cron jobs"
                            :supported-p t)
   (make-adapter-capability :name "acknowledge-alert"
                            :description "Acknowledge alerts"
                            :supported-p t)
   (make-adapter-capability :name "snooze-alert"
                            :description "Snooze alerts for a duration"
                            :supported-p t)
   (make-adapter-capability :name "session-history"
                            :description "Retrieve session message history"
                            :supported-p t)))

;;; ============================================================
;;; Adapter conformance test suite
;;; ============================================================
;;;
;;; Any adapter implementation can run this to verify contract compliance.
;;; Returns (values passed-p failures) where failures is a list of strings.

(declaim (ftype (function (t) (values boolean list)) run-adapter-conformance))
(defun run-adapter-conformance (adapter)
  "Run conformance checks against ADAPTER. Returns (values passed-p failures).
FAILURES is a list of description strings for failed checks."
  (let ((failures '()))
    (flet ((check (description form)
             (unless form
               (push description failures))))

      ;; Query protocol — return type checks
      (let ((sessions (adapter-list-sessions adapter)))
        (check "adapter-list-sessions returns a list"
               (listp sessions))
        (check "adapter-list-sessions elements are session-record"
               (every #'session-record-p sessions)))

      (let ((cron (adapter-list-cron-jobs adapter)))
        (check "adapter-list-cron-jobs returns a list"
               (listp cron))
        (check "adapter-list-cron-jobs elements are cron-record"
               (every #'cron-record-p cron)))

      (let ((health (adapter-system-health adapter)))
        (check "adapter-system-health returns a list"
               (listp health))
        (check "adapter-system-health elements are health-record"
               (every #'health-record-p health)))

      (let ((usage (adapter-usage-records adapter :period :hourly)))
        (check "adapter-usage-records returns a list"
               (listp usage))
        (check "adapter-usage-records elements are usage-record"
               (every #'usage-record-p usage)))

      (let ((events (adapter-tail-events adapter :since 0 :limit 10)))
        (check "adapter-tail-events returns a list"
               (listp events))
        (check "adapter-tail-events respects limit"
               (<= (length events) 10))
        (check "adapter-tail-events elements are event-record"
               (every #'event-record-p events)))

      (let ((alerts (adapter-list-alerts adapter)))
        (check "adapter-list-alerts returns a list"
               (listp alerts))
        (check "adapter-list-alerts elements are alert-record"
               (every #'alert-record-p alerts)))

      (let ((subs (adapter-list-subagents adapter)))
        (check "adapter-list-subagents returns a list"
               (listp subs))
        (check "adapter-list-subagents elements are subagent-record"
               (every #'subagent-record-p subs)))

      ;; Session history — typed return
      (let ((sessions (adapter-list-sessions adapter)))
        (when sessions
          (let ((hist (adapter-session-history adapter
                                              (sr-id (first sessions)))))
            (check "adapter-session-history returns a list"
                   (listp hist))
            (check "adapter-session-history elements are history-entry"
                   (every #'history-entry-p hist)))))

      ;; Capabilities — typed return
      (let ((caps (adapter-capabilities adapter)))
        (check "adapter-capabilities returns a list"
               (listp caps))
        (check "adapter-capabilities elements are adapter-capability"
               (every #'adapter-capability-p caps))
        (check "adapter-capabilities includes trigger-cron"
               (find "trigger-cron" caps :key #'cap-name :test #'string=)))

      ;; Result
      (values (null failures) (nreverse failures)))))
