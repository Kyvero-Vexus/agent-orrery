;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; runtime-transport.lisp — Typed transport boundary + retry policy for live capture
;;;
;;; Provides a typed abstraction over HTTP transport with configurable retry
;;; policies, status mapping, and structured error handling. The capture-driver
;;; calls execute-transport with an injectable transport function, keeping I/O
;;; at the boundary and everything else pure.
;;;
;;; Bead: agent-orrery-q8l

(in-package #:orrery/adapter)

;;; ─── Transport Types ───

(deftype transport-method ()
  "HTTP method for transport requests."
  '(member :get :post :head))

(deftype retry-strategy ()
  "Backoff strategy for retries."
  '(member :none :fixed :exponential))

(deftype transport-outcome-status ()
  "Outcome classification for a transport operation."
  '(member :success :timeout :connection-error :http-error :exhausted))

;;; ─── Retry Policy ───

(defstruct (retry-policy
             (:constructor make-retry-policy
                 (&key (max-attempts 3) (strategy :exponential)
                       (base-delay-ms 500) (max-delay-ms 10000)
                       (retryable-codes '(408 429 500 502 503 504))))
             (:conc-name rp-))
  "Configuration for retry behavior."
  (max-attempts 3 :type (integer 1 100))
  (strategy :exponential :type retry-strategy)
  (base-delay-ms 500 :type (integer 0))
  (max-delay-ms 10000 :type (integer 0))
  (retryable-codes '(408 429 500 502 503 504) :type list))

(defparameter *default-retry-policy*
  (make-retry-policy)
  "Default retry policy: 3 attempts, exponential backoff from 500ms.")

(defparameter *no-retry-policy*
  (make-retry-policy :max-attempts 1 :strategy :none)
  "Single-attempt policy with no retries.")

;;; ─── Transport Request ───

(defstruct (transport-request
             (:constructor make-transport-request
                 (&key (method :get) url (headers '()) (timeout-ms 5000) body))
             (:conc-name treq-))
  "A typed HTTP request."
  (method :get :type transport-method)
  (url "" :type string)
  (headers '() :type list)
  (timeout-ms 5000 :type (integer 0))
  (body nil :type (or null string)))

;;; ─── Transport Response ───

(defstruct (transport-response
             (:constructor make-transport-response
                 (&key (status-code 0) (body "") (headers '()) (latency-ms 0)))
             (:conc-name tresp-))
  "A typed HTTP response."
  (status-code 0 :type (integer 0 999))
  (body "" :type string)
  (headers '() :type list)
  (latency-ms 0 :type (integer 0)))

;;; ─── Transport Attempt ───

(defstruct (transport-attempt
             (:constructor make-transport-attempt
                 (&key (attempt-number 1) response error-class
                       (error-message "") (delay-before-ms 0)))
             (:conc-name ta-))
  "Record of one transport attempt (success or failure)."
  (attempt-number 1 :type (integer 1))
  (response nil :type (or null transport-response))
  (error-class nil :type (or null keyword))
  (error-message "" :type string)
  (delay-before-ms 0 :type (integer 0)))

;;; ─── Transport Outcome ───

(defstruct (transport-outcome
             (:constructor make-transport-outcome
                 (&key (status :success) response (attempts '())
                       (total-ms 0) request))
             (:conc-name tout-))
  "Aggregate result of a transport operation including all retry attempts."
  (status :success :type transport-outcome-status)
  (response nil :type (or null transport-response))
  (attempts '() :type list)
  (total-ms 0 :type (integer 0))
  (request nil :type (or null transport-request)))

;;; ─── Pure Helpers ───

(declaim (ftype (function (retry-policy (integer 1)) (integer 0))
                compute-delay))
(defun compute-delay (policy attempt-number)
  "Compute delay in ms before the given attempt. Pure."
  (declare (optimize (safety 3)))
  (if (<= attempt-number 1)
      0
      (let ((raw (ecase (rp-strategy policy)
                   (:none 0)
                   (:fixed (rp-base-delay-ms policy))
                   (:exponential
                    (* (rp-base-delay-ms policy)
                       (expt 2 (1- (1- attempt-number))))))))
        (min raw (rp-max-delay-ms policy)))))

(declaim (ftype (function (retry-policy (integer 0 999)) t)
                retryable-status-p))
(defun retryable-status-p (policy status-code)
  "Is this HTTP status retryable under the given policy? Pure."
  (declare (optimize (safety 3)))
  (if (member status-code (rp-retryable-codes policy))
      t nil))

(declaim (ftype (function (retry-policy transport-attempt) t)
                retryable-attempt-p))
(defun retryable-attempt-p (policy attempt)
  "Should we retry after this attempt? Pure."
  (declare (optimize (safety 3)))
  (cond
    ;; Transport-level errors (timeout, connection) are always retryable
    ((ta-error-class attempt)
     (if (member (ta-error-class attempt) '(:timeout :connection)) t nil))
    ;; HTTP errors: check retryable codes
    ((ta-response attempt)
     (retryable-status-p policy (tresp-status-code (ta-response attempt))))
    ;; No response and no error class — don't retry
    (t nil)))

(declaim (ftype (function ((integer 0 999)) keyword) map-status-class))
(defun map-status-class (status-code)
  "Map an HTTP status code to a domain classification keyword. Pure."
  (declare (optimize (safety 3)))
  (cond
    ((zerop status-code) :no-response)
    ((and (>= status-code 200) (< status-code 300)) :success)
    ((and (>= status-code 300) (< status-code 400)) :redirect)
    ((= status-code 401) :auth-error)
    ((= status-code 403) :forbidden)
    ((= status-code 404) :not-found)
    ((= status-code 408) :timeout)
    ((= status-code 429) :rate-limited)
    ((and (>= status-code 400) (< status-code 500)) :client-error)
    ((and (>= status-code 500) (< status-code 600)) :server-error)
    (t :unknown)))

(declaim (ftype (function (transport-outcome-status) keyword)
                outcome-status-to-error-class))
(defun outcome-status-to-error-class (status)
  "Map transport outcome status to an error classification. Pure."
  (declare (optimize (safety 3)))
  (ecase status
    (:success :none)
    (:timeout :timeout)
    (:connection-error :connection)
    (:http-error :http)
    (:exhausted :retry-exhausted)))

;;; ─── Outcome → Endpoint Sample ───

(declaim (ftype (function (transport-outcome string (integer 0)) endpoint-sample)
                outcome-to-sample))
(defun outcome-to-sample (outcome endpoint timestamp)
  "Convert a transport outcome to an endpoint-sample for capture-driver. Pure."
  (declare (optimize (safety 3)))
  (let ((resp (tout-response outcome)))
    (ecase (tout-status outcome)
      (:success
       (make-endpoint-sample
        :endpoint endpoint
        :status-code (if resp (tresp-status-code resp) 0)
        :body (if resp (tresp-body resp) "")
        :latency-ms (if resp (tresp-latency-ms resp) (tout-total-ms outcome))
        :timestamp timestamp
        :error-p nil))
      ((:timeout :connection-error)
       (make-endpoint-sample
        :endpoint endpoint
        :status-code 0
        :body ""
        :latency-ms (tout-total-ms outcome)
        :timestamp timestamp
        :error-p t))
      (:http-error
       (make-endpoint-sample
        :endpoint endpoint
        :status-code (if resp (tresp-status-code resp) 0)
        :body (if resp (tresp-body resp) "")
        :latency-ms (if resp (tresp-latency-ms resp) (tout-total-ms outcome))
        :timestamp timestamp
        :error-p t))
      (:exhausted
       (make-endpoint-sample
        :endpoint endpoint
        :status-code (if resp (tresp-status-code resp) 0)
        :body ""
        :latency-ms (tout-total-ms outcome)
        :timestamp timestamp
        :error-p t)))))

;;; ─── Transport Execution (I/O Boundary) ───

(declaim (ftype (function (transport-request function
                           &key (:policy retry-policy)
                                (:sleep-fn (or null function)))
                          transport-outcome)
                execute-transport))
(defun execute-transport (request transport-fn
                          &key (policy *default-retry-policy*)
                               (sleep-fn #'(lambda (ms)
                                             (sleep (/ ms 1000.0)))))
  "Execute a transport request with retry policy. I/O boundary.
   TRANSPORT-FN: (function (transport-request) transport-response)
     — should signal conditions on error, which we catch and classify.
   SLEEP-FN: (function (integer)) — called with delay-ms between retries.
     Inject a no-op for testing."
  (declare (optimize (safety 3)))
  (let ((attempts '())
        (total-start (get-internal-real-time))
        (last-response nil)
        (final-status :exhausted))
    (block transport-loop
      (dotimes (i (rp-max-attempts policy))
        (let* ((attempt-num (1+ i))
               (delay (compute-delay policy attempt-num)))
          ;; Sleep before retry (not before first attempt)
          (when (> delay 0)
            (funcall sleep-fn delay))
          ;; Execute transport
          (handler-case
              (let* ((response (funcall transport-fn request))
                     (sc (tresp-status-code response)))
                (setf last-response response)
                (cond
                  ;; 2xx success
                  ((and (>= sc 200) (< sc 300))
                   (push (make-transport-attempt
                          :attempt-number attempt-num
                          :response response
                          :delay-before-ms delay)
                         attempts)
                   (setf final-status :success)
                   (return-from transport-loop))
                  ;; Retryable HTTP error — no error-class so
                  ;; retryable-attempt-p checks the response status
                  ((retryable-status-p policy sc)
                   (push (make-transport-attempt
                          :attempt-number attempt-num
                          :response response
                          :delay-before-ms delay)
                         attempts))
                  ;; Non-retryable HTTP error
                  (t
                   (push (make-transport-attempt
                          :attempt-number attempt-num
                          :response response
                          :error-class :http
                          :error-message (format nil "HTTP ~D (non-retryable)" sc)
                          :delay-before-ms delay)
                         attempts)
                   (setf final-status :http-error)
                   (return-from transport-loop))))
            ;; Catch transport-level errors
            (error (c)
              (let* ((msg (princ-to-string c))
                     (err-class (cond
                                  ((search "timeout" msg :test #'char-equal) :timeout)
                                  ((search "timed out" msg :test #'char-equal) :timeout)
                                  ((search "connection" msg :test #'char-equal) :connection)
                                  ((search "refused" msg :test #'char-equal) :connection)
                                  (t :unknown))))
                (push (make-transport-attempt
                       :attempt-number attempt-num
                       :response nil
                       :error-class err-class
                       :error-message msg
                       :delay-before-ms delay)
                      attempts)
                (unless (retryable-attempt-p policy (first attempts))
                  (setf final-status
                        (cond
                          ((eq err-class :timeout) :timeout)
                          ((eq err-class :connection) :connection-error)
                          (t :http-error)))
                  (return-from transport-loop))))))))
    ;; Compute total time
    (let ((total-ms (round (* 1000 (/ (- (get-internal-real-time) total-start)
                                      internal-time-units-per-second)))))
      (make-transport-outcome
       :status final-status
       :response last-response
       :attempts (nreverse attempts)
       :total-ms total-ms
       :request request))))

;;; ─── Transport Function Factories ───

(defun make-fixture-transport (fixture-alist)
  "Create a transport function backed by fixture data (alist of path → body).
   Pure — no I/O. For testing and deterministic capture."
  (declare (optimize (safety 3)))
  (lambda (request)
    (declare (type transport-request request))
    (let* ((url (treq-url request))
           ;; Extract path from URL (after host)
           (path (let ((pos (search "/api/" url)))
                   (if pos (subseq url pos) url)))
           (entry (assoc path fixture-alist :test #'string=)))
      (if entry
          (make-transport-response
           :status-code 200
           :body (cdr entry)
           :latency-ms 1)
          (make-transport-response
           :status-code 404
           :body ""
           :latency-ms 1)))))

(defun make-dexador-transport ()
  "Create a transport function using dexador for real HTTP.
   Impure — performs actual network I/O."
  (lambda (request)
    (declare (type transport-request request))
    (let ((start (get-internal-real-time)))
      (multiple-value-bind (body status headers)
          (dex:get (treq-url request)
                   :headers (treq-headers request)
                   :connect-timeout (/ (treq-timeout-ms request) 1000.0)
                   :read-timeout (/ (treq-timeout-ms request) 1000.0))
        (let* ((elapsed (round (* 1000 (/ (- (get-internal-real-time) start)
                                          internal-time-units-per-second))))
               (body-str (etypecase body
                           (string body)
                           ((simple-array (unsigned-byte 8) (*))
                            (babel:octets-to-string body)))))
          (make-transport-response
           :status-code status
           :body body-str
           :headers (if (hash-table-p headers)
                        (let ((alist '()))
                          (maphash (lambda (k v) (push (cons k v) alist)) headers)
                          alist)
                        '())
           :latency-ms elapsed))))))

;;; ─── Convenience: Build Request from Capture Target ───

(declaim (ftype (function (capture-target string) transport-request)
                target-endpoint-request))
(defun target-endpoint-request (target endpoint)
  "Build a transport-request for the given capture target and endpoint path. Pure."
  (declare (optimize (safety 3)))
  (make-transport-request
   :method :get
   :url (format nil "~A~A" (ct-base-url target) endpoint)
   :headers (let ((token (ct-token target)))
              (if (and token (plusp (length token)))
                  (list (cons "Authorization" (format nil "Bearer ~A" token)))
                  '()))
   :timeout-ms (ct-timeout-ms target)))
