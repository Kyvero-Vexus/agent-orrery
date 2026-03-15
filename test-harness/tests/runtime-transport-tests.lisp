;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; runtime-transport-tests.lisp — Tests for runtime transport abstraction
;;;
;;; Bead: agent-orrery-q8l

(in-package #:orrery/harness-tests)

;;; ─── Parent test ───

(define-test runtime-transport)

;;; ─── Retry Policy Defaults ───

(define-test (runtime-transport retry-policy-defaults)
  (let ((p (orrery/adapter:make-retry-policy)))
    (is = 3 (orrery/adapter:rp-max-attempts p))
    (is eq :exponential (orrery/adapter:rp-strategy p))
    (is = 500 (orrery/adapter:rp-base-delay-ms p))
    (is = 10000 (orrery/adapter:rp-max-delay-ms p))
    (is equal '(408 429 500 502 503 504)
        (orrery/adapter:rp-retryable-codes p))))

;;; ─── Compute Delay ───

(define-test (runtime-transport compute-delay-none)
  (let ((p (orrery/adapter:make-retry-policy :strategy :none)))
    (is = 0 (orrery/adapter:compute-delay p 1))
    (is = 0 (orrery/adapter:compute-delay p 2))
    (is = 0 (orrery/adapter:compute-delay p 3))))

(define-test (runtime-transport compute-delay-fixed)
  (let ((p (orrery/adapter:make-retry-policy :strategy :fixed :base-delay-ms 200)))
    (is = 0 (orrery/adapter:compute-delay p 1))
    (is = 200 (orrery/adapter:compute-delay p 2))
    (is = 200 (orrery/adapter:compute-delay p 3))))

(define-test (runtime-transport compute-delay-exponential)
  (let ((p (orrery/adapter:make-retry-policy :strategy :exponential
                                             :base-delay-ms 100
                                             :max-delay-ms 1000)))
    (is = 0 (orrery/adapter:compute-delay p 1))
    (is = 100 (orrery/adapter:compute-delay p 2))   ; 100 * 2^0
    (is = 200 (orrery/adapter:compute-delay p 3))   ; 100 * 2^1
    (is = 400 (orrery/adapter:compute-delay p 4))   ; 100 * 2^2
    (is = 800 (orrery/adapter:compute-delay p 5))   ; 100 * 2^3
    (is = 1000 (orrery/adapter:compute-delay p 6)))) ; capped

;;; ─── Retryable Status ───

(define-test (runtime-transport retryable-status)
  (let ((p orrery/adapter:*default-retry-policy*))
    (true (orrery/adapter:retryable-status-p p 500))
    (true (orrery/adapter:retryable-status-p p 502))
    (true (orrery/adapter:retryable-status-p p 503))
    (true (orrery/adapter:retryable-status-p p 429))
    (true (orrery/adapter:retryable-status-p p 408))
    (false (orrery/adapter:retryable-status-p p 200))
    (false (orrery/adapter:retryable-status-p p 404))
    (false (orrery/adapter:retryable-status-p p 401))
    (false (orrery/adapter:retryable-status-p p 403))))

;;; ─── Map Status Class ───

(define-test (runtime-transport map-status-class)
  (is eq :no-response (orrery/adapter:map-status-class 0))
  (is eq :success (orrery/adapter:map-status-class 200))
  (is eq :success (orrery/adapter:map-status-class 201))
  (is eq :redirect (orrery/adapter:map-status-class 301))
  (is eq :auth-error (orrery/adapter:map-status-class 401))
  (is eq :forbidden (orrery/adapter:map-status-class 403))
  (is eq :not-found (orrery/adapter:map-status-class 404))
  (is eq :timeout (orrery/adapter:map-status-class 408))
  (is eq :rate-limited (orrery/adapter:map-status-class 429))
  (is eq :client-error (orrery/adapter:map-status-class 422))
  (is eq :server-error (orrery/adapter:map-status-class 500))
  (is eq :server-error (orrery/adapter:map-status-class 503)))

;;; ─── Transport Request/Response Construction ───

(define-test (runtime-transport request-construction)
  (let ((req (orrery/adapter:make-transport-request
              :method :get
              :url "http://localhost:3000/api/v1/health"
              :headers '(("Authorization" . "Bearer tok123"))
              :timeout-ms 3000)))
    (is eq :get (orrery/adapter:treq-method req))
    (is string= "http://localhost:3000/api/v1/health"
        (orrery/adapter:treq-url req))
    (is = 3000 (orrery/adapter:treq-timeout-ms req))
    (is = 1 (length (orrery/adapter:treq-headers req)))))

(define-test (runtime-transport response-construction)
  (let ((resp (orrery/adapter:make-transport-response
               :status-code 200
               :body "{\"status\":\"ok\"}"
               :latency-ms 42)))
    (is = 200 (orrery/adapter:tresp-status-code resp))
    (is string= "{\"status\":\"ok\"}" (orrery/adapter:tresp-body resp))
    (is = 42 (orrery/adapter:tresp-latency-ms resp))))

;;; ─── Fixture Transport ───

(define-test (runtime-transport fixture-success)
  (let* ((fixtures '(("/api/v1/health" . "{\"status\":\"ok\"}")
                     ("/api/v1/sessions" . "{\"sessions\":[]}")))
         (tfn (orrery/adapter:make-fixture-transport fixtures))
         (req (orrery/adapter:make-transport-request
               :url "http://fixture/api/v1/health"))
         (resp (funcall tfn req)))
    (is = 200 (orrery/adapter:tresp-status-code resp))
    (is string= "{\"status\":\"ok\"}" (orrery/adapter:tresp-body resp))))

(define-test (runtime-transport fixture-not-found)
  (let* ((fixtures '(("/api/v1/health" . "{\"status\":\"ok\"}")))
         (tfn (orrery/adapter:make-fixture-transport fixtures))
         (req (orrery/adapter:make-transport-request
               :url "http://fixture/api/v1/missing"))
         (resp (funcall tfn req)))
    (is = 404 (orrery/adapter:tresp-status-code resp))))

;;; ─── Execute Transport: Success ───

(define-test (runtime-transport execute-success)
  (let* ((tfn (lambda (req)
                (declare (ignore req))
                (orrery/adapter:make-transport-response
                 :status-code 200
                 :body "ok"
                 :latency-ms 10)))
         (req (orrery/adapter:make-transport-request :url "http://test/api/v1/health"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy orrery/adapter:*default-retry-policy*
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    (is eq :success (orrery/adapter:tout-status outcome))
    (is = 1 (length (orrery/adapter:tout-attempts outcome)))
    (true (orrery/adapter:tout-response outcome))
    (is = 200 (orrery/adapter:tresp-status-code
                (orrery/adapter:tout-response outcome)))))

;;; ─── Execute Transport: Retry then Succeed ───

(define-test (runtime-transport execute-retry-then-succeed)
  (let* ((call-count 0)
         (tfn (lambda (req)
                (declare (ignore req))
                (incf call-count)
                (if (< call-count 3)
                    (orrery/adapter:make-transport-response
                     :status-code 503
                     :body "unavailable"
                     :latency-ms 5)
                    (orrery/adapter:make-transport-response
                     :status-code 200
                     :body "recovered"
                     :latency-ms 10))))
         (req (orrery/adapter:make-transport-request :url "http://test/api"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy (orrery/adapter:make-retry-policy
                            :max-attempts 5
                            :strategy :none)
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    (is eq :success (orrery/adapter:tout-status outcome))
    (is = 3 call-count)
    (is = 3 (length (orrery/adapter:tout-attempts outcome)))
    (is = 200 (orrery/adapter:tresp-status-code
                (orrery/adapter:tout-response outcome)))))

;;; ─── Execute Transport: Exhausted Retries ───

(define-test (runtime-transport execute-exhausted)
  (let* ((tfn (lambda (req)
                (declare (ignore req))
                (orrery/adapter:make-transport-response
                 :status-code 503
                 :body "down"
                 :latency-ms 5)))
         (req (orrery/adapter:make-transport-request :url "http://test/api"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy (orrery/adapter:make-retry-policy :max-attempts 3
                                                             :strategy :none)
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    (is eq :exhausted (orrery/adapter:tout-status outcome))
    (is = 3 (length (orrery/adapter:tout-attempts outcome)))))

;;; ─── Execute Transport: Non-retryable Error ───

(define-test (runtime-transport execute-non-retryable)
  (let* ((call-count 0)
         (tfn (lambda (req)
                (declare (ignore req))
                (incf call-count)
                (orrery/adapter:make-transport-response
                 :status-code 401
                 :body "unauthorized"
                 :latency-ms 2)))
         (req (orrery/adapter:make-transport-request :url "http://test/api"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy orrery/adapter:*default-retry-policy*
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    ;; Should NOT retry on 401
    (is = 1 call-count)
    (is eq :http-error (orrery/adapter:tout-status outcome))
    (is = 1 (length (orrery/adapter:tout-attempts outcome)))))

;;; ─── Execute Transport: Timeout Error ───

(define-test (runtime-transport execute-timeout)
  (let* ((call-count 0)
         (tfn (lambda (req)
                (declare (ignore req))
                (incf call-count)
                (error "Connection timed out")))
         (req (orrery/adapter:make-transport-request :url "http://test/api"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy (orrery/adapter:make-retry-policy :max-attempts 2
                                                             :strategy :none)
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    (is = 2 call-count)
    (is eq :exhausted (orrery/adapter:tout-status outcome))
    (is = 2 (length (orrery/adapter:tout-attempts outcome)))
    ;; First attempt should have :timeout error class
    (is eq :timeout
        (orrery/adapter:ta-error-class (first (orrery/adapter:tout-attempts outcome))))))

;;; ─── Execute Transport: Connection Refused ───

(define-test (runtime-transport execute-connection-refused)
  (let* ((call-count 0)
         (tfn (lambda (req)
                (declare (ignore req))
                (incf call-count)
                (error "Connection refused")))
         (req (orrery/adapter:make-transport-request :url "http://test/api"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy (orrery/adapter:make-retry-policy :max-attempts 2
                                                             :strategy :none)
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    (is = 2 call-count)
    (is eq :exhausted (orrery/adapter:tout-status outcome))
    (is eq :connection
        (orrery/adapter:ta-error-class (first (orrery/adapter:tout-attempts outcome))))))

;;; ─── Execute Transport: No Retry Policy ───

(define-test (runtime-transport execute-no-retry)
  (let* ((call-count 0)
         (tfn (lambda (req)
                (declare (ignore req))
                (incf call-count)
                (orrery/adapter:make-transport-response
                 :status-code 503
                 :body "down"
                 :latency-ms 5)))
         (req (orrery/adapter:make-transport-request :url "http://test/api"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy orrery/adapter:*no-retry-policy*
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    ;; Single attempt only
    (is = 1 call-count)
    (is = 1 (length (orrery/adapter:tout-attempts outcome)))))

;;; ─── Outcome to Sample ───

(define-test (runtime-transport outcome-to-sample-success)
  (let* ((resp (orrery/adapter:make-transport-response
                :status-code 200
                :body "{\"ok\":true}"
                :latency-ms 42))
         (outcome (orrery/adapter:make-transport-outcome
                   :status :success
                   :response resp
                   :total-ms 42))
         (sample (orrery/adapter:outcome-to-sample outcome "/api/v1/health" 1000)))
    (is string= "/api/v1/health" (orrery/adapter:es-endpoint sample))
    (is = 200 (orrery/adapter:es-status-code sample))
    (is string= "{\"ok\":true}" (orrery/adapter:es-body sample))
    (is = 42 (orrery/adapter:es-latency-ms sample))
    (is = 1000 (orrery/adapter:es-timestamp sample))
    (false (orrery/adapter:es-error-p sample))))

(define-test (runtime-transport outcome-to-sample-timeout)
  (let* ((outcome (orrery/adapter:make-transport-outcome
                   :status :timeout
                   :response nil
                   :total-ms 5000))
         (sample (orrery/adapter:outcome-to-sample outcome "/api/v1/health" 2000)))
    (is = 0 (orrery/adapter:es-status-code sample))
    (is = 5000 (orrery/adapter:es-latency-ms sample))
    (true (orrery/adapter:es-error-p sample))))

(define-test (runtime-transport outcome-to-sample-http-error)
  (let* ((resp (orrery/adapter:make-transport-response
                :status-code 401
                :body "unauthorized"
                :latency-ms 15))
         (outcome (orrery/adapter:make-transport-outcome
                   :status :http-error
                   :response resp
                   :total-ms 15))
         (sample (orrery/adapter:outcome-to-sample outcome "/api/v1/sessions" 3000)))
    (is = 401 (orrery/adapter:es-status-code sample))
    (true (orrery/adapter:es-error-p sample))))

(define-test (runtime-transport outcome-to-sample-exhausted)
  (let* ((outcome (orrery/adapter:make-transport-outcome
                   :status :exhausted
                   :response nil
                   :total-ms 15000))
         (sample (orrery/adapter:outcome-to-sample outcome "/api/v1/health" 4000)))
    (is = 0 (orrery/adapter:es-status-code sample))
    (is = 15000 (orrery/adapter:es-latency-ms sample))
    (true (orrery/adapter:es-error-p sample))))

;;; ─── Target Endpoint Request ───

(define-test (runtime-transport target-endpoint-request)
  (let* ((target (orrery/adapter:make-capture-target
                  :base-url "http://localhost:3000"
                  :token "tok123"
                  :profile :live
                  :timeout-ms 3000))
         (req (orrery/adapter:target-endpoint-request target "/api/v1/health")))
    (is eq :get (orrery/adapter:treq-method req))
    (is string= "http://localhost:3000/api/v1/health"
        (orrery/adapter:treq-url req))
    (is = 3000 (orrery/adapter:treq-timeout-ms req))
    ;; Should have auth header
    (is = 1 (length (orrery/adapter:treq-headers req)))
    (is string= "Authorization"
        (car (first (orrery/adapter:treq-headers req))))))

(define-test (runtime-transport target-endpoint-request-no-token)
  (let* ((target (orrery/adapter:make-capture-target
                  :base-url "http://localhost:3000"
                  :token ""
                  :profile :live))
         (req (orrery/adapter:target-endpoint-request target "/api/v1/health")))
    ;; No auth header when token is empty
    (is = 0 (length (orrery/adapter:treq-headers req)))))

;;; ─── Integration: Fixture Transport + Execute ───

(define-test (runtime-transport integration-fixture-execute)
  (let* ((fixtures '(("/api/v1/health" . "{\"status\":\"ok\"}")
                     ("/api/v1/sessions" . "{\"sessions\":[]}")))
         (tfn (orrery/adapter:make-fixture-transport fixtures))
         (target (orrery/adapter:make-capture-target
                  :base-url "http://fixture"
                  :profile :fixture))
         (req (orrery/adapter:target-endpoint-request target "/api/v1/health"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy orrery/adapter:*no-retry-policy*
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    (is eq :success (orrery/adapter:tout-status outcome))
    (is = 200 (orrery/adapter:tresp-status-code
                (orrery/adapter:tout-response outcome)))
    ;; Convert to sample
    (let ((sample (orrery/adapter:outcome-to-sample outcome "/api/v1/health" 100)))
      (false (orrery/adapter:es-error-p sample))
      (is = 200 (orrery/adapter:es-status-code sample))
      (is string= "{\"status\":\"ok\"}" (orrery/adapter:es-body sample)))))

;;; ─── Integration: Fixture 404 → Sample ───

(define-test (runtime-transport integration-fixture-404)
  (let* ((fixtures '(("/api/v1/health" . "{\"status\":\"ok\"}")))
         (tfn (orrery/adapter:make-fixture-transport fixtures))
         (req (orrery/adapter:make-transport-request :url "http://fixture/api/v1/missing"))
         (outcome (orrery/adapter:execute-transport
                   req tfn
                   :policy orrery/adapter:*no-retry-policy*
                   :sleep-fn (lambda (ms) (declare (ignore ms))))))
    ;; 404 is non-retryable HTTP error
    (is eq :http-error (orrery/adapter:tout-status outcome))
    (let ((sample (orrery/adapter:outcome-to-sample outcome "/api/v1/missing" 100)))
      (true (orrery/adapter:es-error-p sample))
      (is = 404 (orrery/adapter:es-status-code sample)))))

;;; ─── Retryable Attempt ───

(define-test (runtime-transport retryable-attempt-p)
  (let ((policy orrery/adapter:*default-retry-policy*))
    ;; Timeout error → retryable
    (true (orrery/adapter:retryable-attempt-p
           policy
           (orrery/adapter:make-transport-attempt
            :error-class :timeout :error-message "timeout")))
    ;; Connection error → retryable
    (true (orrery/adapter:retryable-attempt-p
           policy
           (orrery/adapter:make-transport-attempt
            :error-class :connection :error-message "refused")))
    ;; Unknown error → NOT retryable
    (false (orrery/adapter:retryable-attempt-p
            policy
            (orrery/adapter:make-transport-attempt
             :error-class :unknown :error-message "wat")))
    ;; 503 response → retryable
    (true (orrery/adapter:retryable-attempt-p
           policy
           (orrery/adapter:make-transport-attempt
            :response (orrery/adapter:make-transport-response
                       :status-code 503))))
    ;; 401 response → NOT retryable
    (false (orrery/adapter:retryable-attempt-p
            policy
            (orrery/adapter:make-transport-attempt
             :response (orrery/adapter:make-transport-response
                        :status-code 401))))))
