;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; transcript-capture-tests.lisp — Tests for transcript capture + replay

(in-package #:orrery/harness-tests)

(define-test transcript-capture-tests)

;;; ─── Capture ───

(define-test (transcript-capture-tests capture-response-entry)
  (let ((entry (orrery/adapter:capture-response
                "/health" :get 200 "application/json"
                "{\"status\":\"ok\"}")))
    (true (orrery/adapter:transcript-entry-p entry))
    (is eq :response (orrery/adapter:te-direction entry))
    (is eq :get (orrery/adapter:te-method entry))
    (is string= "/health" (orrery/adapter:te-path entry))
    (is = 200 (orrery/adapter:te-status-code entry))
    (true (plusp (orrery/adapter:te-timestamp entry)))))

(define-test (transcript-capture-tests build-transcript)
  (let* ((e1 (orrery/adapter:capture-response
              "/health" :get 200 "application/json" "{}"))
         (e2 (orrery/adapter:capture-response
              "/sessions" :get 200 "application/json" "[]"))
         (tx (orrery/adapter:build-transcript "test-capture" (list e1 e2))))
    (true (orrery/adapter:transcript-p tx))
    (is string= "test-capture" (orrery/adapter:tx-name tx))
    (is = 2 (length (orrery/adapter:tx-entries tx)))))

;;; ─── Replay ───

(define-test (transcript-capture-tests replay-valid-transcript)
  (let* ((e1 (orrery/adapter:capture-response
              "/health" :get 200 "application/json" "{}"))
         (tx (orrery/adapter:build-transcript "replay-test" (list e1)))
         (result (orrery/adapter:replay-transcript tx)))
    (is eq :pass (orrery/adapter:rr-replay-verdict result))
    (is = 1 (length (orrery/adapter:rr-matches result)))
    (is = 0 (length (orrery/adapter:rr-mismatches result)))))

(define-test (transcript-capture-tests replay-malformed-entry)
  (let* ((bad (orrery/adapter:make-transcript-entry
               :direction :response :method :get :path ""
               :status-code 0 :content-type "" :body ""))
         (tx (orrery/adapter:build-transcript "bad" (list bad)))
         (result (orrery/adapter:replay-transcript tx)))
    (is eq :fail (orrery/adapter:rr-replay-verdict result))
    (is = 1 (length (orrery/adapter:rr-mismatches result)))))

(define-test (transcript-capture-tests replay-mixed-entries)
  (let* ((good (orrery/adapter:capture-response
                "/health" :get 200 "application/json" "{}"))
         (bad (orrery/adapter:make-transcript-entry
               :direction :response :path "" :status-code 0))
         (tx (orrery/adapter:build-transcript "mixed" (list good bad)))
         (result (orrery/adapter:replay-transcript tx)))
    (is eq :fail (orrery/adapter:rr-replay-verdict result))
    (is = 1 (length (orrery/adapter:rr-matches result)))
    (is = 1 (length (orrery/adapter:rr-mismatches result)))))

;;; ─── JSON ───

(define-test (transcript-capture-tests json-roundtrip-structure)
  (let* ((e1 (orrery/adapter:capture-response
              "/health" :get 200 "application/json" "{\"ok\":true}"))
         (tx (orrery/adapter:build-transcript "json-test" (list e1)))
         (json (orrery/adapter:transcript-to-json tx)))
    (true (search "\"name\":\"json-test\"" json))
    (true (search "\"path\":\"/health\"" json))
    (true (search "\"status_code\":200" json))
    (true (search "\"entries\":[" json))))

(define-test (transcript-capture-tests json-escaping-in-body)
  (let* ((e1 (orrery/adapter:capture-response
              "/test" :get 200 "application/json"
              "{\"msg\":\"has \\\"quotes\\\"\"}"))
         (tx (orrery/adapter:build-transcript "escape" (list e1)))
         (json (orrery/adapter:transcript-to-json tx)))
    (true (search "\\\"" json))))

(define-test (transcript-capture-tests load-from-json-valid)
  (let ((tx (orrery/adapter:load-transcript-from-json "{\"name\":\"test\"}")))
    (true (orrery/adapter:transcript-p tx))))

(define-test (transcript-capture-tests load-from-json-invalid)
  (let ((tx (orrery/adapter:load-transcript-from-json "not json")))
    (true (null tx))))

(define-test (transcript-capture-tests empty-transcript-replay)
  (let* ((tx (orrery/adapter:build-transcript "empty" '()))
         (result (orrery/adapter:replay-transcript tx)))
    (is eq :pass (orrery/adapter:rr-replay-verdict result))
    (is = 0 (length (orrery/adapter:rr-matches result)))))
