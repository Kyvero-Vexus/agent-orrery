;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; handshake-probe-tests.lisp — Tests for live-runtime handshake probe

(in-package #:orrery/harness-tests)

(define-test handshake-probe-tests)

;;; Response family classification
(define-test (handshake-probe-tests classify-auth-gated)
  (let* ((ec (orrery/adapter/openclaw:make-endpoint-classification
              :path "/health" :surface :error :http-status 401
              :content-type "" :body-shape :empty :confidence 0.5))
         (family (orrery/adapter/openclaw:classify-response-family ec 401)))
    (is eq :auth-gated family)))

(define-test (handshake-probe-tests classify-openclaw-json)
  (let* ((ec (orrery/adapter/openclaw:make-endpoint-classification
              :path "/health" :surface :openclaw-json :http-status 200
              :content-type "application/json" :body-shape :json-object :confidence 0.95))
         (family (orrery/adapter/openclaw:classify-response-family ec 200)))
    (is eq :openclaw-api family)))

(define-test (handshake-probe-tests classify-html-control)
  (let* ((ec (orrery/adapter/openclaw:make-endpoint-classification
              :path "/sessions" :surface :html-control-plane :http-status 200
              :content-type "text/html" :body-shape :html :confidence 0.9))
         (family (orrery/adapter/openclaw:classify-response-family ec 200)))
    (is eq :html-control-plane family)))

;;; Remediation hint generation
(define-test (handshake-probe-tests remediation-for-auth)
  (let ((hint (orrery/adapter/openclaw:make-family-remediation
               :auth-gated "http://localhost/health")))
    (is eq :authentication-required (orrery/adapter/openclaw:rh-problem hint))
    (true (search "ORRERY_OPENCLAW_TOKEN" (orrery/adapter/openclaw:rh-suggestion hint)))))

(define-test (handshake-probe-tests remediation-for-html)
  (let ((hint (orrery/adapter/openclaw:make-family-remediation
               :html-control-plane "http://localhost/sessions")))
    (is eq :html-detected (orrery/adapter/openclaw:rh-problem hint))
    (true (search "API" (orrery/adapter/openclaw:rh-suggestion hint)))))

;;; Handshake report
(define-test (handshake-probe-tests run-probe-report)
  (let ((report (orrery/adapter/openclaw:run-handshake-probe
                 "http://localhost:18789"
                 '("/health" "/sessions" "/unknown"))))
    (true (orrery/adapter/openclaw:handshake-report-p report))
    (is = 3 (length (orrery/adapter/openclaw:hr-results report)))
    (true (stringp (orrery/adapter/openclaw:hr-summary report)))))
