;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; openclaw.lisp — OpenClaw adapter client
;;;
;;; Implements the orrery/adapter protocol against OpenClaw-compatible HTTP APIs.
;;; This version includes full read surfaces, robust normalization, and error mapping.

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
;;; OpenClaw-specific typed conditions
;;; ============================================================

(define-condition openclaw-transport-error (adapter-error)
  ((status :initarg :status :reader openclaw-transport-status :initform nil :type (or null fixnum))
   (path :initarg :path :reader openclaw-transport-path :initform "" :type string))
  (:documentation "Transport-layer error (request/HTTP failure) from OpenClaw adapter."))

(define-condition openclaw-decode-error (adapter-error)
  ((path :initarg :path :reader openclaw-decode-path :initform "" :type string)
   (reason :initarg :reason :reader openclaw-decode-reason :initform "decode failure" :type string))
  (:documentation "Raised when OpenClaw payload cannot be decoded to expected shape."))

;;; ============================================================
;;; HTTP helpers
;;; ============================================================

(declaim (ftype (function (openclaw-adapter string) string) %path-url)
         (ftype (function (openclaw-adapter) list) %headers)
         (ftype (function (t string &optional t) t) %field)
         (ftype (function (t &optional fixnum) fixnum) %int)
         (ftype (function (t keyword) keyword) %kw)
         (ftype (function (t) boolean) %ok-payload-p)
         (ftype (function (openclaw-adapter t keyword &optional t) *) %signal-payload-error)
         (ftype (function (openclaw-adapter keyword string keyword &key (:payload t)) list)
                %request-result-list)
         (ftype (function (openclaw-adapter) list) openclaw-fetch-sessions)
         (ftype (function (openclaw-adapter) list) openclaw-fetch-cron-jobs)
         (ftype (function (openclaw-adapter) list) openclaw-fetch-health)
         (ftype (function (list) list) openclaw-decode-sessions)
         (ftype (function (list) list) openclaw-decode-cron-jobs)
         (ftype (function (list) list) openclaw-decode-health)
         (ftype (function (t) session-record) %parse-session)
         (ftype (function (t) history-entry) %parse-history-entry)
         (ftype (function (t) cron-record) %parse-cron)
         (ftype (function (t) health-record) %parse-health))

(defun %path-url (adapter path)
  (declare (type openclaw-adapter adapter)
           (type string path))
  (format nil "~A~A" (string-right-trim "/" (openclaw-base-url adapter)) path))

(defun %headers (adapter)
  (declare (type openclaw-adapter adapter))
  (if (openclaw-api-token adapter)
      `(("Authorization" . ,(format nil "Bearer ~A" (openclaw-api-token adapter))))
      '()))

(defgeneric %openclaw-request (adapter method path &key payload)
  (:documentation "Internal request hook. Tests specialize this to avoid network I/O."))

(defmethod %openclaw-request ((adapter openclaw-adapter) method path &key payload)
  (declare (ignore payload)
           (type keyword method)
           (type string path))
  (let ((url (%path-url adapter path))
        (headers (%headers adapter)))
    (handler-case
        (com.inuoe.jzon:parse
         (handler-case
             (ecase method
               (:get
                (dexador:get url :headers headers :connect-timeout (openclaw-timeout-s adapter)))
               (:post
                (dexador:post url :headers headers :connect-timeout (openclaw-timeout-s adapter)
                              :content "{}")))
           (dexador.error:http-request-failed (e)
             ;; Normalize HTTP failures into adapter conditions.
             (let ((status (ignore-errors (dexador.error:response-status e))))
               (cond
                 ((= status 404)
                  (error 'adapter-not-found :adapter adapter :operation :http :id path))
                 ((= status 501)
                  (error 'adapter-not-supported :adapter adapter :operation :http))
                 (t
                  (error 'openclaw-transport-error
                         :adapter adapter
                         :operation :http
                         :status status
                         :path path)))))))
      (error (e)
        (if (typep e 'adapter-error)
            (error e)
            (error 'openclaw-decode-error
                   :adapter adapter
                   :operation :decode
                   :path path
                   :reason (princ-to-string e)))))))

(defun %field (ht key &optional default)
  (if (hash-table-p ht)
      (multiple-value-bind (v presentp) (gethash key ht)
        (if presentp v default))
      default))

(defun %int (value &optional (default 0))
  "Best-effort integer coercion for robust normalization."
  (cond
    ((integerp value) value)
    ((floatp value) (truncate value))
    ((stringp value) (or (ignore-errors (parse-integer value)) default))
    (t default)))

(defun %kw (value fallback)
  "Normalize VALUE to an uppercase keyword; return FALLBACK on failure."
  (let* ((s (cond
              ((keywordp value) (symbol-name value))
              ((stringp value) value)
              ((symbolp value) (symbol-name value))
              (t nil)))
         (k (and s (ignore-errors (intern (string-upcase s) :keyword)))))
    (or k fallback)))

(defun %ok-payload-p (payload)
  "OpenClaw-style APIs commonly return {\"ok\": true, \"result\": ...}.
If \"ok\" is absent, treat payload as OK for compatibility."
  (let ((ok (%field payload "ok" :missing)))
    (or (eq ok :missing) ok)))

(defun %signal-payload-error (adapter payload operation &optional id)
  (let ((code (or (%field payload "error_code" nil)
                  (%field payload "code" nil)
                  (%field payload "error" nil))))
    (cond
      ((or (equal code 404)
           (string-equal (princ-to-string code) "NOT_FOUND"))
       (error 'adapter-not-found :adapter adapter :operation operation :id (or id "unknown")))
      ((or (equal code 501)
           (string-equal (princ-to-string code) "NOT_SUPPORTED"))
       (error 'adapter-not-supported :adapter adapter :operation operation))
      (t
       (error 'adapter-error :adapter adapter :operation operation)))))

(defun %request-result-list (adapter method path operation &key payload)
  "Request PATH and normalize OpenClaw payload to a list result.
Signals adapter conditions on explicit API errors." 
  (let* ((resp (%openclaw-request adapter method path :payload payload)))
    (unless (%ok-payload-p resp)
      (%signal-payload-error adapter resp operation path))
    (let ((r (%field resp "result" nil)))
      (cond
        ((vectorp r) (coerce r 'list))
        ((listp r) r)
        ((hash-table-p r) (list r))
        ;; Some endpoints return the object directly (no "result").
        ((hash-table-p resp) (list resp))
        (t '())))))

(defun %parse-session (obj)
  (make-session-record
   :id (or (%field obj "id" "") "")
   :agent-name (or (%field obj "agent" (%field obj "agent_name" "")) "")
   :channel (or (%field obj "channel" "") "")
   :status (%kw (%field obj "status" :active) :active)
   :model (or (%field obj "model" "") "")
   :created-at (%int (%field obj "created_at" 0))
   :updated-at (%int (%field obj "updated_at" 0))
   :message-count (%int (%field obj "message_count" 0))
   :total-tokens (%int (%field obj "total_tokens" 0))
   :estimated-cost-cents (%int (%field obj "estimated_cost_cents" 0))))

(defun %parse-history-entry (obj)
  (make-history-entry
   :role (%kw (%field obj "role" :user) :user)
   :content (or (%field obj "content" (%field obj "text" "")) "")
   :timestamp (%int (%field obj "timestamp" 0))
   :token-count (%int (%field obj "token_count" (%field obj "tokens" 0)))))

(defun %parse-cron (obj)
  (make-cron-record
   :name (or (%field obj "name" "") "")
   :kind (%kw (%field obj "kind" :periodic) :periodic)
   :interval-s (%int (%field obj "interval_s" 0))
   :status (%kw (%field obj "status" :active) :active)
   :last-run-at (let ((v (%field obj "last_run_at" nil)))
                  (and v (%int v)))
   :next-run-at (%int (%field obj "next_run_at" 0))
   :run-count (%int (%field obj "run_count" 0))
   :last-error (%field obj "last_error" nil)
   :description (or (%field obj "description" "") "")))

(defun %parse-health (obj)
  (make-health-record
   :component (or (%field obj "component" "") "")
   :status (%kw (%field obj "status" :ok) :ok)
   :message (or (%field obj "message" "") "")
   :checked-at (%int (%field obj "checked_at" 0))
   :latency-ms (%int (%field obj "latency_ms" (%field obj "latency" 0)))))

(defun %parse-usage (obj)
  (make-usage-record
   :model (or (%field obj "model" "") "")
   :period (%kw (%field obj "period" :hourly) :hourly)
   :timestamp (%int (%field obj "timestamp" 0))
   :prompt-tokens (%int (%field obj "prompt_tokens" 0))
   :completion-tokens (%int (%field obj "completion_tokens" 0))
   :total-tokens (%int (%field obj "total_tokens" 0))
   :estimated-cost-cents (%int (%field obj "estimated_cost_cents" 0))))

(defun %parse-event (obj)
  (make-event-record
   :id (or (%field obj "id" "") "")
   :kind (%kw (%field obj "kind" :info) :info)
   :source (or (%field obj "source" "") "")
   :message (or (%field obj "message" "") "")
   :timestamp (%int (%field obj "timestamp" 0))
   :metadata (%field obj "metadata" nil)))

(defun %parse-alert (obj)
  (make-alert-record
   :id (or (%field obj "id" "") "")
   :severity (%kw (%field obj "severity" :warning) :warning)
   :title (or (%field obj "title" "") "")
   :message (or (%field obj "message" "") "")
   :source (or (%field obj "source" "") "")
   :fired-at (%int (%field obj "fired_at" 0))
   :acknowledged-p (not (null (%field obj "acknowledged" (%field obj "acknowledged_p" nil))))
   :snoozed-until (let ((v (%field obj "snoozed_until" nil)))
                    (and v (%int v)))))

(defun %parse-subagent (obj)
  (make-subagent-record
   :id (or (%field obj "id" "") "")
   :parent-session (or (%field obj "parent_session" "") "")
   :agent-name (or (%field obj "agent_name" (%field obj "agent" "")) "")
   :status (%kw (%field obj "status" :running) :running)
   :started-at (%int (%field obj "started_at" 0))
   :finished-at (let ((v (%field obj "finished_at" nil)))
                  (and v (%int v)))
   :total-tokens (%int (%field obj "total_tokens" 0))
   :result (%field obj "result" nil)))

;;; ============================================================
;;; Adapter protocol methods
;;; ============================================================

(defun openclaw-fetch-sessions (adapter)
  "Impure transport primitive: fetch raw session payload list."
  (declare (type openclaw-adapter adapter))
  (%request-result-list adapter :get "/sessions" :sessions))

(defun openclaw-decode-sessions (objects)
  "Pure decode primitive: convert raw payload objects into SESSION-RECORD values."
  (declare (type list objects))
  (mapcar #'%parse-session objects))

(defmethod adapter-list-sessions ((adapter openclaw-adapter))
  (openclaw-decode-sessions (openclaw-fetch-sessions adapter)))

(defmethod adapter-session-history ((adapter openclaw-adapter) session-id)
  (mapcar #'%parse-history-entry
          (%request-result-list adapter :get
                                (format nil "/sessions/~A/history" session-id)
                                :session-history)))

(defun openclaw-fetch-cron-jobs (adapter)
  "Impure transport primitive: fetch raw cron payload list."
  (declare (type openclaw-adapter adapter))
  (%request-result-list adapter :get "/cron/jobs" :cron-jobs))

(defun openclaw-decode-cron-jobs (objects)
  "Pure decode primitive: convert raw payload objects into CRON-RECORD values."
  (declare (type list objects))
  (mapcar #'%parse-cron objects))

(defmethod adapter-list-cron-jobs ((adapter openclaw-adapter))
  (openclaw-decode-cron-jobs (openclaw-fetch-cron-jobs adapter)))

(defmethod adapter-trigger-cron ((adapter openclaw-adapter) job-name)
  (let ((resp (%request-result-list adapter :post
                                    (format nil "/cron/jobs/~A/run" job-name)
                                    :trigger-cron)))
    (declare (ignore resp))
    t))

(defmethod adapter-pause-cron ((adapter openclaw-adapter) job-name)
  (let ((resp (%request-result-list adapter :post
                                    (format nil "/cron/jobs/~A/pause" job-name)
                                    :pause-cron)))
    (declare (ignore resp))
    t))

(defmethod adapter-resume-cron ((adapter openclaw-adapter) job-name)
  (let ((resp (%request-result-list adapter :post
                                    (format nil "/cron/jobs/~A/resume" job-name)
                                    :resume-cron)))
    (declare (ignore resp))
    t))

(defun openclaw-fetch-health (adapter)
  "Impure transport primitive: fetch raw health payload list."
  (declare (type openclaw-adapter adapter))
  (%request-result-list adapter :get "/health" :health))

(defun openclaw-decode-health (objects)
  "Pure decode primitive: convert raw payload objects into HEALTH-RECORD values."
  (declare (type list objects))
  (mapcar #'%parse-health objects))

(defmethod adapter-system-health ((adapter openclaw-adapter))
  (openclaw-decode-health (openclaw-fetch-health adapter)))

(defmethod adapter-usage-records ((adapter openclaw-adapter) &key (period :hourly))
  (declare (ignore period))
  (mapcar #'%parse-usage
          (%request-result-list adapter :get "/usage" :usage)))

(defmethod adapter-tail-events ((adapter openclaw-adapter) &key (since 0) (limit 50))
  (declare (ignore since limit))
  (mapcar #'%parse-event
          (%request-result-list adapter :get "/events" :events)))

(defmethod adapter-list-alerts ((adapter openclaw-adapter))
  (mapcar #'%parse-alert
          (%request-result-list adapter :get "/alerts" :alerts)))

(defmethod adapter-acknowledge-alert ((adapter openclaw-adapter) alert-id)
  (let ((resp (%request-result-list adapter :post
                                    (format nil "/alerts/~A/ack" alert-id)
                                    :acknowledge-alert)))
    (declare (ignore resp))
    t))

(defmethod adapter-snooze-alert ((adapter openclaw-adapter) alert-id duration-seconds)
  (declare (ignore duration-seconds))
  (let ((resp (%request-result-list adapter :post
                                    (format nil "/alerts/~A/snooze" alert-id)
                                    :snooze-alert)))
    (declare (ignore resp))
    t))

(defmethod adapter-list-subagents ((adapter openclaw-adapter))
  (mapcar #'%parse-subagent
          (%request-result-list adapter :get "/subagents" :subagents)))

(defmethod adapter-capabilities ((adapter openclaw-adapter))
  (declare (ignore adapter))
  ;; Must match implemented methods.
  (list
   (make-adapter-capability :name "trigger-cron" :description "Trigger cron runs" :supported-p t)
   (make-adapter-capability :name "pause-cron" :description "Pause cron jobs" :supported-p t)
   (make-adapter-capability :name "resume-cron" :description "Resume cron jobs" :supported-p t)
   (make-adapter-capability :name "session-history" :description "Read session histories" :supported-p t)
   (make-adapter-capability :name "acknowledge-alert" :description "Acknowledge alerts" :supported-p t)
   (make-adapter-capability :name "snooze-alert" :description "Snooze alerts" :supported-p t)
   (make-adapter-capability :name "usage" :description "Usage analytics" :supported-p t)
   (make-adapter-capability :name "events" :description "Event tail" :supported-p t)
   (make-adapter-capability :name "subagents" :description "Sub-agent listing" :supported-p t)))
