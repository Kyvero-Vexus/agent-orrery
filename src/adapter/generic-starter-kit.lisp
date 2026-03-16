;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; generic-starter-kit.lisp — Generic adapter starter kit for non-OpenClaw runtimes
;;;
;;; Bead: agent-orrery-eb0.6.2

(in-package #:orrery/adapter)

(defstruct (starter-endpoint-spec (:conc-name ses-))
  "One endpoint mapping in the starter adapter.

KEY identifies the protocol operation (e.g. :sessions, :cron-trigger).
DECODE-FN converts transport payload to typed values.
RESULT-MODE is one of :list :object :boolean.
"
  (key :sessions :type keyword)
  (method :get :type keyword)
  (path "/sessions" :type string)
  (decode-fn #'identity :type function)
  (result-mode :list :type keyword)
  (capability-name "" :type string)
  (description "" :type string)
  (supported-p t :type boolean))

(defclass generic-runtime-adapter ()
  ((adapter-name :initarg :adapter-name :reader starter-adapter-name :type string)
   (base-url :initarg :base-url :reader starter-base-url :type string)
   (request-fn :initarg :request-fn :reader starter-request-fn :type function)
   (endpoint-table :initarg :endpoint-table :reader starter-endpoint-table :type hash-table))
  (:documentation "Reference adapter for non-OpenClaw runtimes."))

(declaim
 (ftype (function (t string &optional t) t) %starter-field)
 (ftype (function (t &optional fixnum) fixnum) %starter-int)
 (ftype (function (t keyword) keyword) %starter-kw)
 (ftype (function (generic-runtime-adapter keyword)
                  (values (or null starter-endpoint-spec) &optional))
        find-starter-endpoint)
 (ftype (function (generic-runtime-adapter starter-endpoint-spec)
                  (values generic-runtime-adapter &optional))
        register-starter-endpoint)
 (ftype (function (generic-runtime-adapter keyword &key (:payload t))
                  (values t &optional))
        invoke-starter-endpoint)
 (ftype (function (&key (:adapter-name string)
                        (:base-url string)
                        (:request-fn function)
                        (:endpoint-specs list))
                  (values generic-runtime-adapter &optional))
        make-generic-runtime-adapter)
 (ftype (function () (values list &optional))
        make-default-starter-endpoint-specs)
 (ftype (function (&key (:adapter-name string)
                        (:base-url string)
                        (:request-fn function))
                  (values generic-runtime-adapter &optional))
        make-reference-starter-adapter))

(defun %starter-field (ht key &optional default)
  (if (hash-table-p ht)
      (multiple-value-bind (v presentp) (gethash key ht)
        (if presentp v default))
      default))

(defun %starter-int (value &optional (default 0))
  (cond
    ((integerp value) value)
    ((floatp value) (truncate value))
    ((stringp value) (or (ignore-errors (parse-integer value)) default))
    (t default)))

(defun %starter-kw (value fallback)
  (let* ((s (cond
              ((keywordp value) (symbol-name value))
              ((stringp value) value)
              ((symbolp value) (symbol-name value))
              (t nil)))
         (k (and s (ignore-errors (intern (string-upcase s) :keyword)))))
    (or k fallback)))

(defun %decode-session (obj)
  (orrery/domain:make-session-record
   :id (or (%starter-field obj "id" "") "")
   :agent-name (or (%starter-field obj "agent" (%starter-field obj "agent_name" "")) "")
   :channel (or (%starter-field obj "channel" "") "")
   :status (%starter-kw (%starter-field obj "status" :active) :active)
   :model (or (%starter-field obj "model" "") "")
   :created-at (%starter-int (%starter-field obj "created_at" 0))
   :updated-at (%starter-int (%starter-field obj "updated_at" 0))
   :message-count (%starter-int (%starter-field obj "message_count" 0))
   :total-tokens (%starter-int (%starter-field obj "total_tokens" 0))
   :estimated-cost-cents (%starter-int (%starter-field obj "estimated_cost_cents" 0))))

(defun %decode-history-entry (obj)
  (orrery/domain:make-history-entry
   :role (%starter-kw (%starter-field obj "role" :user) :user)
   :content (or (%starter-field obj "content" (%starter-field obj "text" "")) "")
   :timestamp (%starter-int (%starter-field obj "timestamp" 0))
   :token-count (%starter-int (%starter-field obj "token_count" (%starter-field obj "tokens" 0)))))

(defun %decode-cron (obj)
  (orrery/domain:make-cron-record
   :name (or (%starter-field obj "name" "") "")
   :kind (%starter-kw (%starter-field obj "kind" :periodic) :periodic)
   :interval-s (%starter-int (%starter-field obj "interval_s" 0))
   :status (%starter-kw (%starter-field obj "status" :active) :active)
   :last-run-at (let ((v (%starter-field obj "last_run_at" nil))) (and v (%starter-int v)))
   :next-run-at (%starter-int (%starter-field obj "next_run_at" 0))
   :run-count (%starter-int (%starter-field obj "run_count" 0))
   :last-error (%starter-field obj "last_error" nil)
   :description (or (%starter-field obj "description" "") "")))

(defun %decode-health (obj)
  (orrery/domain:make-health-record
   :component (or (%starter-field obj "component" "") "")
   :status (%starter-kw (%starter-field obj "status" :ok) :ok)
   :message (or (%starter-field obj "message" "") "")
   :checked-at (%starter-int (%starter-field obj "checked_at" 0))
   :latency-ms (%starter-int (%starter-field obj "latency_ms" 0))))

(defun %decode-usage (obj)
  (orrery/domain:make-usage-record
   :model (or (%starter-field obj "model" "") "")
   :period (%starter-kw (%starter-field obj "period" :hourly) :hourly)
   :timestamp (%starter-int (%starter-field obj "timestamp" 0))
   :prompt-tokens (%starter-int (%starter-field obj "prompt_tokens" 0))
   :completion-tokens (%starter-int (%starter-field obj "completion_tokens" 0))
   :total-tokens (%starter-int (%starter-field obj "total_tokens" 0))
   :estimated-cost-cents (%starter-int (%starter-field obj "estimated_cost_cents" 0))))

(defun %decode-event (obj)
  (orrery/domain:make-event-record
   :id (or (%starter-field obj "id" "") "")
   :kind (%starter-kw (%starter-field obj "kind" :info) :info)
   :source (or (%starter-field obj "source" "") "")
   :message (or (%starter-field obj "message" "") "")
   :timestamp (%starter-int (%starter-field obj "timestamp" 0))
   :metadata (%starter-field obj "metadata" nil)))

(defun %decode-alert (obj)
  (orrery/domain:make-alert-record
   :id (or (%starter-field obj "id" "") "")
   :severity (%starter-kw (%starter-field obj "severity" :warning) :warning)
   :title (or (%starter-field obj "title" "") "")
   :message (or (%starter-field obj "message" "") "")
   :source (or (%starter-field obj "source" "") "")
   :fired-at (%starter-int (%starter-field obj "fired_at" 0))
   :acknowledged-p (not (null (%starter-field obj "acknowledged" nil)))
   :snoozed-until (let ((v (%starter-field obj "snoozed_until" nil))) (and v (%starter-int v)))))

(defun %decode-subagent (obj)
  (orrery/domain:make-subagent-record
   :id (or (%starter-field obj "id" "") "")
   :parent-session (or (%starter-field obj "parent_session" "") "")
   :agent-name (or (%starter-field obj "agent_name" (%starter-field obj "agent" "")) "")
   :status (%starter-kw (%starter-field obj "status" :running) :running)
   :started-at (%starter-int (%starter-field obj "started_at" 0))
   :finished-at (let ((v (%starter-field obj "finished_at" nil))) (and v (%starter-int v)))
   :total-tokens (%starter-int (%starter-field obj "total_tokens" 0))
   :result (%starter-field obj "result" nil)))

(defun make-default-starter-endpoint-specs ()
  (list
   (make-starter-endpoint-spec :key :sessions :method :get :path "/sessions" :decode-fn #'%decode-session :result-mode :list :capability-name "sessions" :description "List sessions")
   (make-starter-endpoint-spec :key :history :method :get :path "/sessions/{id}/history" :decode-fn #'%decode-history-entry :result-mode :list :capability-name "session-history" :description "Session history")
   (make-starter-endpoint-spec :key :cron-jobs :method :get :path "/cron/jobs" :decode-fn #'%decode-cron :result-mode :list :capability-name "cron" :description "List cron jobs")
   (make-starter-endpoint-spec :key :health :method :get :path "/health" :decode-fn #'%decode-health :result-mode :list :capability-name "health" :description "Health")
   (make-starter-endpoint-spec :key :usage :method :get :path "/usage" :decode-fn #'%decode-usage :result-mode :list :capability-name "usage" :description "Usage")
   (make-starter-endpoint-spec :key :events :method :get :path "/events" :decode-fn #'%decode-event :result-mode :list :capability-name "events" :description "Events")
   (make-starter-endpoint-spec :key :alerts :method :get :path "/alerts" :decode-fn #'%decode-alert :result-mode :list :capability-name "alerts" :description "Alerts")
   (make-starter-endpoint-spec :key :subagents :method :get :path "/subagents" :decode-fn #'%decode-subagent :result-mode :list :capability-name "subagents" :description "Subagents")
   (make-starter-endpoint-spec :key :cron-trigger :method :post :path "/cron/jobs/{job}/run" :result-mode :boolean :capability-name "trigger-cron" :description "Trigger cron")
   (make-starter-endpoint-spec :key :cron-pause :method :post :path "/cron/jobs/{job}/pause" :result-mode :boolean :capability-name "pause-cron" :description "Pause cron")
   (make-starter-endpoint-spec :key :cron-resume :method :post :path "/cron/jobs/{job}/resume" :result-mode :boolean :capability-name "resume-cron" :description "Resume cron")
   (make-starter-endpoint-spec :key :alert-ack :method :post :path "/alerts/{id}/ack" :result-mode :boolean :capability-name "acknowledge-alert" :description "Acknowledge alert")
   (make-starter-endpoint-spec :key :alert-snooze :method :post :path "/alerts/{id}/snooze" :result-mode :boolean :capability-name "snooze-alert" :description "Snooze alert")))

(defun make-generic-runtime-adapter (&key (adapter-name "generic-runtime")
                                          (base-url "http://localhost:8080")
                                          request-fn
                                          (endpoint-specs (make-default-starter-endpoint-specs)))
  (let ((table (make-hash-table :test #'eq)))
    (dolist (spec endpoint-specs)
      (setf (gethash (ses-key spec) table) spec))
    (make-instance 'generic-runtime-adapter
                   :adapter-name adapter-name
                   :base-url base-url
                   :request-fn (or request-fn (lambda (&rest args) (declare (ignore args)) nil))
                   :endpoint-table table)))

(defun make-reference-starter-adapter (&key (adapter-name "generic-runtime")
                                            (base-url "http://localhost:8080")
                                            request-fn)
  (make-generic-runtime-adapter
   :adapter-name adapter-name
   :base-url base-url
   :request-fn request-fn
   :endpoint-specs (make-default-starter-endpoint-specs)))

(defun find-starter-endpoint (adapter key)
  (nth-value 0 (gethash key (starter-endpoint-table adapter))))

(defun register-starter-endpoint (adapter spec)
  (setf (gethash (ses-key spec) (starter-endpoint-table adapter)) spec)
  adapter)

(defun %replace-all (s from to)
  (declare (type string s from to))
  (with-output-to-string (out)
    (loop with pos = 0
          for hit = (search from s :start2 pos)
          do (if hit
                 (progn
                   (write-string s out :start pos :end hit)
                   (write-string to out)
                   (setf pos (+ hit (length from))))
                 (progn
                   (write-string s out :start pos)
                   (return))))))

(defun %path-subst (template pairs)
  (declare (type string template) (type list pairs))
  (reduce (lambda (acc pair)
            (destructuring-bind (placeholder value) pair
              (%replace-all acc placeholder (princ-to-string value))))
          pairs
          :initial-value template))

(defun %normalize-result-list (payload)
  (cond
    ((null payload) nil)
    ((vectorp payload) (coerce payload 'list))
    ((listp payload) payload)
    ((hash-table-p payload)
     (let ((result (%starter-field payload "result" nil)))
       (cond
         ((vectorp result) (coerce result 'list))
         ((listp result) result)
         ((hash-table-p result) (list result))
         (t (list payload)))))
    (t nil)))

(defun invoke-starter-endpoint (adapter key &key payload)
  (declare (type generic-runtime-adapter adapter)
           (type keyword key))
  (let ((spec (find-starter-endpoint adapter key)))
    (unless spec
      (error 'adapter-not-supported :adapter adapter :operation key))
    (let* ((method (ses-method spec))
           (path (ses-path spec))
           (response (funcall (starter-request-fn adapter) adapter method path :payload payload))
           (mode (ses-result-mode spec)))
      (ecase mode
        (:boolean (not (null response)))
        (:object (funcall (ses-decode-fn spec) response))
        (:list (mapcar (ses-decode-fn spec) (%normalize-result-list response)))))))

(defun %invoke-with-subst (adapter key substitutions &key payload)
  (declare (type list substitutions))
  (let ((spec (find-starter-endpoint adapter key)))
    (unless spec
      (error 'adapter-not-supported :adapter adapter :operation key))
    (let* ((patched (copy-starter-endpoint-spec spec))
           (path (%path-subst (ses-path spec) substitutions)))
      (setf (ses-path patched) path)
      (register-starter-endpoint adapter patched)
      (unwind-protect
           (invoke-starter-endpoint adapter key :payload payload)
        (register-starter-endpoint adapter spec)))))

(defmethod adapter-list-sessions ((adapter generic-runtime-adapter))
  (invoke-starter-endpoint adapter :sessions))

(defmethod adapter-session-history ((adapter generic-runtime-adapter) session-id)
  (%invoke-with-subst adapter :history (list (list "{id}" session-id))))

(defmethod adapter-list-cron-jobs ((adapter generic-runtime-adapter))
  (invoke-starter-endpoint adapter :cron-jobs))

(defmethod adapter-system-health ((adapter generic-runtime-adapter))
  (invoke-starter-endpoint adapter :health))

(defmethod adapter-usage-records ((adapter generic-runtime-adapter) &key (period :hourly))
  (declare (ignore period))
  (invoke-starter-endpoint adapter :usage))

(defmethod adapter-tail-events ((adapter generic-runtime-adapter) &key (since 0) (limit 50))
  (declare (ignore since limit))
  (invoke-starter-endpoint adapter :events))

(defmethod adapter-list-alerts ((adapter generic-runtime-adapter))
  (invoke-starter-endpoint adapter :alerts))

(defmethod adapter-list-subagents ((adapter generic-runtime-adapter))
  (invoke-starter-endpoint adapter :subagents))

(defmethod adapter-trigger-cron ((adapter generic-runtime-adapter) job-name)
  (%invoke-with-subst adapter :cron-trigger (list (list "{job}" job-name))))

(defmethod adapter-pause-cron ((adapter generic-runtime-adapter) job-name)
  (%invoke-with-subst adapter :cron-pause (list (list "{job}" job-name))))

(defmethod adapter-resume-cron ((adapter generic-runtime-adapter) job-name)
  (%invoke-with-subst adapter :cron-resume (list (list "{job}" job-name))))

(defmethod adapter-acknowledge-alert ((adapter generic-runtime-adapter) alert-id)
  (%invoke-with-subst adapter :alert-ack (list (list "{id}" alert-id))))

(defmethod adapter-snooze-alert ((adapter generic-runtime-adapter) alert-id duration-seconds)
  (%invoke-with-subst adapter :alert-snooze (list (list "{id}" alert-id))
                      :payload (list :duration-seconds duration-seconds)))

(defmethod adapter-capabilities ((adapter generic-runtime-adapter))
  (let ((caps nil))
    (maphash (lambda (k spec)
               (declare (ignore k))
               (when (> (length (ses-capability-name spec)) 0)
                 (push (orrery/domain:make-adapter-capability
                        :name (ses-capability-name spec)
                        :description (ses-description spec)
                        :supported-p (ses-supported-p spec))
                       caps)))
             (starter-endpoint-table adapter))
    (nreverse caps)))
