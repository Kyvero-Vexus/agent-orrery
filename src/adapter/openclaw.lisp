;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; openclaw.lisp — OpenClaw adapter client (Epic 2 checkpoint)
;;;
;;; Implements the orrery/adapter protocol against OpenClaw-compatible HTTP APIs.
;;; This checkpoint focuses on health/sessions/cron/history (+ trigger-cron).

(in-package #:orrery/adapter/openclaw)

;;; ============================================================
;;; Adapter class
;;; ============================================================

(defclass openclaw-adapter ()
  ((base-url :initarg :base-url :reader openclaw-base-url :type string)
   (api-token :initarg :api-token :reader openclaw-api-token :initform nil)
   (timeout-s :initarg :timeout-s :reader openclaw-timeout-s :initform 10))
  (:documentation "HTTP client adapter for OpenClaw-compatible runtimes."))

(declaim (ftype (function (&key (:base-url string)
                                (:api-token (or null string))
                                (:timeout-s fixnum))
                         openclaw-adapter)
                make-openclaw-adapter))
(defun make-openclaw-adapter (&key (base-url "http://localhost:7474")
                                   (api-token nil)
                                   (timeout-s 10))
  "Create an OpenClaw adapter client." 
  (make-instance 'openclaw-adapter
                 :base-url base-url
                 :api-token api-token
                 :timeout-s timeout-s))

;;; ============================================================
;;; HTTP helpers
;;; ============================================================

(defun %path-url (adapter path)
  (format nil "~A~A" (string-right-trim "/" (openclaw-base-url adapter)) path))

(defun %headers (adapter)
  (if (openclaw-api-token adapter)
      `(("Authorization" . ,(format nil "Bearer ~A" (openclaw-api-token adapter))))
      '()))

(defgeneric %openclaw-request (adapter method path &key payload)
  (:documentation "Internal request hook. Tests can specialize this to avoid network I/O."))

(defmethod %openclaw-request ((adapter openclaw-adapter) method path &key payload)
  (declare (ignore payload))
  (let ((url (%path-url adapter path))
        (headers (%headers adapter)))
    (com.inuoe.jzon:parse
     (ecase method
       (:get
        (dexador:get url :headers headers :connect-timeout (openclaw-timeout-s adapter)))
       (:post
        (dexador:post url :headers headers :connect-timeout (openclaw-timeout-s adapter)
                      :content "{}"))))))

(defun %field (ht key &optional default)
  (if (hash-table-p ht)
      (multiple-value-bind (v presentp) (gethash key ht)
        (if presentp v default))
      default))

(defun %result-list (payload)
  (let ((r (%field payload "result" nil)))
    (cond
      ((vectorp r) (coerce r 'list))
      ((listp r) r)
      (t '()))))

(defun %parse-session (obj)
  (make-session-record
   :id (or (%field obj "id" "") "")
   :agent-name (or (%field obj "agent" "") "")
   :channel (or (%field obj "channel" "") "")
   :status (or (ignore-errors (intern (string-upcase (or (%field obj "status" "active") "active")) :keyword))
               :active)
   :model (or (%field obj "model" "") "")
   :created-at (or (%field obj "created_at" 0) 0)
   :updated-at (or (%field obj "updated_at" 0) 0)
   :message-count (or (%field obj "message_count" 0) 0)
   :total-tokens (or (%field obj "total_tokens" 0) 0)
   :estimated-cost-cents (or (%field obj "estimated_cost_cents" 0) 0)))

(defun %parse-history-entry (obj)
  (make-history-entry
   :role (or (ignore-errors (intern (string-upcase (or (%field obj "role" "user") "user")) :keyword))
             :user)
   :content (or (%field obj "content" "") "")
   :timestamp (or (%field obj "timestamp" 0) 0)
   :token-count (or (%field obj "token_count" 0) 0)))

(defun %parse-cron (obj)
  (make-cron-record
   :name (or (%field obj "name" "") "")
   :kind (or (ignore-errors (intern (string-upcase (or (%field obj "kind" "periodic") "periodic")) :keyword))
             :periodic)
   :interval-s (or (%field obj "interval_s" 0) 0)
   :status (or (ignore-errors (intern (string-upcase (or (%field obj "status" "active") "active")) :keyword))
               :active)
   :last-run-at (%field obj "last_run_at" nil)
   :next-run-at (or (%field obj "next_run_at" 0) 0)
   :run-count (or (%field obj "run_count" 0) 0)
   :last-error (%field obj "last_error" nil)
   :description (or (%field obj "description" "") "")))

(defun %parse-health (obj)
  (make-health-record
   :component (or (%field obj "component" "") "")
   :status (or (ignore-errors (intern (string-upcase (or (%field obj "status" "ok") "ok")) :keyword))
               :ok)
   :message (or (%field obj "message" "") "")
   :checked-at (or (%field obj "checked_at" 0) 0)
   :latency-ms (or (%field obj "latency_ms" 0) 0)))

;;; ============================================================
;;; Adapter protocol methods
;;; ============================================================

(defmethod adapter-list-sessions ((adapter openclaw-adapter))
  (mapcar #'%parse-session
          (%result-list (%openclaw-request adapter :get "/sessions"))))

(defmethod adapter-session-history ((adapter openclaw-adapter) session-id)
  (mapcar #'%parse-history-entry
          (%result-list (%openclaw-request adapter :get
                                           (format nil "/sessions/~A/history" session-id)))))

(defmethod adapter-list-cron-jobs ((adapter openclaw-adapter))
  (mapcar #'%parse-cron
          (%result-list (%openclaw-request adapter :get "/cron/jobs"))))

(defmethod adapter-trigger-cron ((adapter openclaw-adapter) job-name)
  (let ((resp (%openclaw-request adapter :post (format nil "/cron/jobs/~A/run" job-name))))
    (declare (ignore resp))
    t))

(defmethod adapter-pause-cron ((adapter openclaw-adapter) job-name)
  (let ((resp (%openclaw-request adapter :post (format nil "/cron/jobs/~A/pause" job-name))))
    (declare (ignore resp))
    t))

(defmethod adapter-resume-cron ((adapter openclaw-adapter) job-name)
  (let ((resp (%openclaw-request adapter :post (format nil "/cron/jobs/~A/resume" job-name))))
    (declare (ignore resp))
    t))

(defmethod adapter-system-health ((adapter openclaw-adapter))
  (let* ((payload (%openclaw-request adapter :get "/health"))
         (components (%result-list payload)))
    (if components
        (mapcar #'%parse-health components)
        ;; Some APIs return a single status object instead of result list.
        (list (%parse-health payload)))))

(defmethod adapter-usage-records ((adapter openclaw-adapter) &key period)
  (declare (ignore period))
  (error 'adapter-not-supported :adapter adapter :operation :usage))

(defmethod adapter-tail-events ((adapter openclaw-adapter) &key since limit)
  (declare (ignore since limit))
  (error 'adapter-not-supported :adapter adapter :operation :events))

(defmethod adapter-list-alerts ((adapter openclaw-adapter))
  (error 'adapter-not-supported :adapter adapter :operation :alerts))

(defmethod adapter-acknowledge-alert ((adapter openclaw-adapter) alert-id)
  (declare (ignore alert-id))
  (error 'adapter-not-supported :adapter adapter :operation :acknowledge-alert))

(defmethod adapter-snooze-alert ((adapter openclaw-adapter) alert-id duration-seconds)
  (declare (ignore alert-id duration-seconds))
  (error 'adapter-not-supported :adapter adapter :operation :snooze-alert))

(defmethod adapter-list-subagents ((adapter openclaw-adapter))
  (error 'adapter-not-supported :adapter adapter :operation :subagents))

(defmethod adapter-capabilities ((adapter openclaw-adapter))
  (declare (ignore adapter))
  (list
   (make-adapter-capability :name "trigger-cron" :description "Trigger cron runs" :supported-p t)
   (make-adapter-capability :name "pause-cron" :description "Pause cron jobs" :supported-p t)
   (make-adapter-capability :name "resume-cron" :description "Resume cron jobs" :supported-p t)
   (make-adapter-capability :name "session-history" :description "Read session histories" :supported-p t)
   (make-adapter-capability :name "acknowledge-alert" :description "Acknowledge alerts" :supported-p nil)
   (make-adapter-capability :name "snooze-alert" :description "Snooze alerts" :supported-p nil)
   (make-adapter-capability :name "usage" :description "Usage analytics" :supported-p nil)
   (make-adapter-capability :name "events" :description "Event tail" :supported-p nil)
   (make-adapter-capability :name "subagents" :description "Sub-agent listing" :supported-p nil)))
