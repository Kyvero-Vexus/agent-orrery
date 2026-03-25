;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; live-adapter.lisp — Live HTTP-polling adapter for OpenClaw gateway (eb0.12.1)
;;;
;;; Polls OpenClaw REST endpoints at a configurable interval and returns typed
;;; domain records.  Connection failures degrade gracefully: empty lists are
;;; returned and a warning is logged rather than signalling.
;;;
;;; SSE subscription lives in the same file (eb0.12.2): see LIVE-ADAPTER-SSE
;;; section below.

(in-package #:orrery/live-adapter)

;;; ============================================================
;;; Config struct
;;; ============================================================

(defstruct (live-adapter-config
            (:constructor make-live-adapter-config
                (&key (host "localhost")
                      (port 7777)
                      (poll-interval-s 5)
                      (timeout-s 10)
                      (api-token nil))))
  "Configuration for the live OpenClaw HTTP-polling adapter."
  (host           "localhost" :type string)
  (port           7777        :type fixnum)
  (poll-interval-s 5         :type fixnum)
  (timeout-s      10         :type fixnum)
  (api-token      nil        :type (or null string)))

(declaim
 (ftype (function (&key (:host string)
                        (:port fixnum)
                        (:poll-interval-s fixnum)
                        (:timeout-s fixnum)
                        (:api-token (or null string)))
                  live-adapter-config)
        make-live-adapter-config))

;;; ============================================================
;;; Internal HTTP helpers
;;; ============================================================

(declaim (ftype (function (live-adapter-config string) string)
                %live-base-url))
(defun %live-base-url (config path)
  "Return absolute URL for PATH on the configured host/port."
  (format nil "http://~a:~a~a"
          (live-adapter-config-host config)
          (live-adapter-config-port config)
          path))

(declaim (ftype (function (live-adapter-config) list)
                %live-headers))
(defun %live-headers (config)
  "Build request headers, including Bearer token if configured."
  (let ((base '(("Accept" . "application/json"))))
    (if (live-adapter-config-api-token config)
        (cons (cons "Authorization"
                    (concatenate 'string "Bearer "
                                 (live-adapter-config-api-token config)))
              base)
        base)))

(declaim (ftype (function (live-adapter-config string) (or null t))
                %live-get-json))
(defun %live-get-json (config path)
  "GET PATH from OpenClaw gateway. Returns parsed JSON or NIL on error."
  (handler-case
      (let* ((url (%live-base-url config path))
             (response (dex:get url
                                :headers (%live-headers config)
                                :connect-timeout (live-adapter-config-timeout-s config)
                                :read-timeout (live-adapter-config-timeout-s config))))
        (com.inuoe.jzon:parse response))
    (dex:http-request-failed (e)
      (warn "live-adapter: HTTP error on ~a: ~a" path e)
      nil)
    (error (e)
      (warn "live-adapter: connection error on ~a: ~a" path e)
      nil)))

;;; ============================================================
;;; Public polling functions (eb0.12.1)
;;; ============================================================

(declaim (ftype (function (live-adapter-config) boolean)
                check-openclaw-reachable))
(defun check-openclaw-reachable (config)
  "Return T if the OpenClaw health endpoint responds, NIL otherwise."
  (handler-case
      (let ((url (%live-base-url config "/api/health")))
        (multiple-value-bind (body status)
            (dex:get url
                     :headers (%live-headers config)
                     :connect-timeout (live-adapter-config-timeout-s config)
                     :read-timeout (live-adapter-config-timeout-s config))
          (declare (ignore body))
          (< status 500)))
    (error ()
      nil)))

(declaim (ftype (function (live-adapter-config) list)
                poll-openclaw-sessions))
(defun poll-openclaw-sessions (config)
  "Return list of SESSION-RECORD from /api/sessions, or NIL on failure."
  (let ((payload (%live-get-json config "/api/sessions")))
    (when payload
      (%decode-sessions payload))))

(declaim (ftype (function (live-adapter-config) list)
                poll-openclaw-cron))
(defun poll-openclaw-cron (config)
  "Return list of CRON-RECORD from /api/cron, or NIL on failure."
  (let ((payload (%live-get-json config "/api/cron")))
    (when payload
      (%decode-cron payload))))

(declaim (ftype (function (live-adapter-config) list)
                poll-openclaw-health))
(defun poll-openclaw-health (config)
  "Return list of HEALTH-RECORD from /api/health, or NIL on failure."
  (let ((payload (%live-get-json config "/api/health")))
    (when payload
      (%decode-health payload))))

;;; ============================================================
;;; Decoders
;;; ============================================================

(declaim (ftype (function (t) list) %decode-sessions %decode-cron %decode-health))

(defun %field (obj key &optional default)
  "Extract KEY from hash-table OBJ, returning DEFAULT when absent."
  (if (hash-table-p obj)
      (gethash key obj default)
      default))

(defun %str (v &optional (default ""))
  "Coerce V to string or return DEFAULT."
  (cond ((stringp v) v)
        ((null v) default)
        (t (princ-to-string v))))

(defun %int (v &optional (default 0))
  "Coerce V to integer or return DEFAULT."
  (cond ((integerp v) v)
        ((null v) default)
        (t default)))

(defun %decode-sessions (payload)
  "Decode JSON payload into list of SESSION-RECORD."
  (let ((items (cond ((listp payload) payload)
                     ((and (hash-table-p payload)
                           (gethash "sessions" payload))
                      (gethash "sessions" payload))
                     (t nil))))
    (loop for item in items
          when (hash-table-p item)
          collect (orrery/domain:make-session-record
                   :id         (%str (%field item "id"))
                   :agent-name (%str (%field item "name"))
                   :status     (intern (string-upcase
                                        (%str (%field item "status") "active"))
                                       :keyword)
                   :model      (%str (%field item "model"))
                   :channel    (%str (%field item "channel"))
                   :created-at (%int (%field item "created_at"))
                   :updated-at (%int (%field item "updated_at"))))))

(defun %decode-cron (payload)
  "Decode JSON payload into list of CRON-RECORD."
  (let ((items (cond ((listp payload) payload)
                     ((and (hash-table-p payload)
                           (gethash "jobs" payload))
                      (gethash "jobs" payload))
                     (t nil))))
    (loop for item in items
          when (hash-table-p item)
          collect (orrery/domain:make-cron-record
                   :name        (%str (%field item "name"))
                   :description (%str (%field item "description"))
                   :kind        (intern (string-upcase
                                         (%str (%field item "kind") "periodic"))
                                        :keyword)
                   :status      (intern (string-upcase
                                          (%str (%field item "status") "active"))
                                         :keyword)
                   :interval-s  (%int (%field item "interval_s"))
                   :last-run-at (let ((v (%field item "last_run_at")))
                                  (if v (%int v) nil))
                   :next-run-at (%int (%field item "next_run_at"))
                   :run-count   (%int (%field item "run_count"))))))

(defun %decode-health (payload)
  "Decode JSON payload into list of HEALTH-RECORD (one per component)."
  (cond
    ;; Flat health object → single record
    ((and (hash-table-p payload) (gethash "status" payload))
     (list (orrery/domain:make-health-record
            :component  (%str (%field payload "component" "gateway"))
            :status     (intern (string-upcase
                                  (%str (%field payload "status" "unknown")))
                                 :keyword)
            :message    (%str (%field payload "message"))
            :checked-at (%int (%field payload "checked_at"))
            :latency-ms (%int (%field payload "latency_ms")))))
    ;; Array of component health objects
    ((listp payload)
     (loop for item in payload
           when (hash-table-p item)
           collect (orrery/domain:make-health-record
                    :component  (%str (%field item "component" "unknown"))
                    :status     (intern (string-upcase
                                          (%str (%field item "status" "unknown")))
                                         :keyword)
                    :message    (%str (%field item "message"))
                    :checked-at (%int (%field item "checked_at"))
                    :latency-ms (%int (%field item "latency_ms")))))
    (t nil)))

;;; ============================================================
;;; SSE subscription (eb0.12.2)
;;; ============================================================

(defstruct (sse-subscription
            (:constructor %make-sse-subscription (url thread stop-flag)))
  "Handle for an active SSE event-stream subscription."
  (url       "" :type string)
  (thread    nil)
  (stop-flag nil))

(declaim
 (ftype (function (live-adapter-config function) sse-subscription)
        start-sse-subscription)
 (ftype (function (sse-subscription) null)
        stop-sse-subscription))

(defun %parse-sse-line (line state)
  "Parse a single SSE protocol line into STATE plist. Returns updated state."
  (cond
    ((zerop (length line))
     ;; Blank line → dispatch event if data present
     (let ((data  (getf state :data))
           (etype (getf state :event "message"))
           (id    (getf state :id)))
       (declare (ignore id))
       (when data
         (list :dispatch (list etype data)
               :data nil :event nil :id (getf state :id))))
     )
    ((and (>= (length line) 6) (string= (subseq line 0 6) "data: "))
     (list* :data (subseq line 6) state))
    ((and (>= (length line) 7) (string= (subseq line 0 7) "event: "))
     (list* :event (subseq line 7) state))
    ((and (>= (length line) 4) (string= (subseq line 0 4) "id: "))
     (list* :id (subseq line 4) state))
    (t state)))

(defun %sse-reader-loop (config event-handler stop-flag)
  "Internal loop: connect, read SSE lines, dispatch events, reconnect on error."
  (let ((url (%live-base-url config "/api/events"))
        (backoff 1))
    (loop
      (when (car stop-flag) (return))
      (handler-case
          (let ((stream (dex:get url
                                 :headers (list* '("Accept" . "text/event-stream")
                                                 (%live-headers config))
                                 :want-stream t
                                 :connect-timeout (live-adapter-config-timeout-s config)
                                 :read-timeout 0)))   ; streaming: no read timeout
            (setf backoff 1)
            (let ((state '(:data nil :event nil :id nil)))
              (loop
                (when (car stop-flag) (return))
                (let ((line (read-line stream nil nil)))
                  (when (null line) (return))
                  (let* ((new-state (%parse-sse-line line state))
                         (dispatch  (getf new-state :dispatch)))
                    (setf state (progn
                                  (remf new-state :dispatch)
                                  new-state))
                    (when dispatch
                      (handler-case
                          (funcall event-handler (first dispatch) (second dispatch))
                        (error (e)
                          (warn "live-adapter SSE: handler error: ~a" e)))))))))
        (error (e)
          (warn "live-adapter SSE: disconnected (~a), reconnecting in ~as" e backoff)
          (sleep backoff)
          (setf backoff (min 60 (* 2 backoff))))))))

(defun start-sse-subscription (config event-handler)
  "Start a background SSE subscription thread. EVENT-HANDLER is called with
(event-type event-data-string) for each incoming event.
Returns an SSE-SUBSCRIPTION handle; pass to STOP-SSE-SUBSCRIPTION to cancel."
  (let* ((stop-flag (list nil))
         (thread (bt:make-thread
                  (lambda ()
                    (%sse-reader-loop config event-handler stop-flag))
                  :name "orrery-live-sse")))
    (%make-sse-subscription (%live-base-url config "/api/events") thread stop-flag)))

(defun stop-sse-subscription (sub)
  "Signal the SSE reader thread to stop. Returns NIL."
  (setf (car (sse-subscription-stop-flag sub)) t)
  (when (sse-subscription-thread sub)
    (handler-case (bt:destroy-thread (sse-subscription-thread sub))
      (error ())))
  nil)
