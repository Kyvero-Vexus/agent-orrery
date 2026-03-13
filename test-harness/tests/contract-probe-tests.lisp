;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; contract-probe-tests.lisp — tests for live-endpoint contract probe diagnostics

(in-package #:orrery/harness-tests)

(define-test contract-probe-tests)

(define-test (contract-probe-tests html-endpoint-mismatch)
  (let* ((report (openclaw-live-contract-probe :base-url "http://127.0.0.1:18789" :timeout-s 2))
         (results (probe-report-results report))
         (sessions (find "/sessions" results
                         :key #'probe-endpoint-result-endpoint
                         :test #'string=)))
    (true (probe-report-p report))
    (false (probe-report-overall-ok-p report))
    (true sessions)
    (false (probe-endpoint-result-ok-p sessions))))
