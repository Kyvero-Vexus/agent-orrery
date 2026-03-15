;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; decision-core-tests.lisp — Tests for decision-core health gate arbitration
;;;

(in-package #:orrery/harness-tests)

(define-test decision-core)

;;; ─── classify-probe-status ───

(define-test (decision-core classify-pass-clean)
  (is eq :healthy (classify-probe-status :pass :clean)))

(define-test (decision-core classify-pass-drifted)
  (is eq :degraded (classify-probe-status :pass :drifted)))

(define-test (decision-core classify-blocked-external)
  (is eq :degraded (classify-probe-status :blocked-external :clean)))

(define-test (decision-core classify-fail)
  (is eq :unhealthy (classify-probe-status :fail :clean)))

(define-test (decision-core classify-inconclusive)
  (is eq :unknown (classify-probe-status :inconclusive :clean)))

(define-test (decision-core classify-fail-drifted)
  (is eq :unhealthy (classify-probe-status :fail :drifted)))

;;; ─── status-to-severity ───

(define-test (decision-core severity-healthy-transport)
  (is = 0 (status-to-severity :healthy :transport)))

(define-test (decision-core severity-healthy-auth)
  (is = 15 (status-to-severity :healthy :auth)))

(define-test (decision-core severity-unhealthy-auth)
  (is = 90 (status-to-severity :unhealthy :auth)))

(define-test (decision-core severity-unhealthy-schema)
  (is = 85 (status-to-severity :unhealthy :schema)))

(define-test (decision-core severity-degraded-runtime)
  (is = 35 (status-to-severity :degraded :runtime)))

(define-test (decision-core severity-unknown-capability)
  (is = 45 (status-to-severity :unknown :capability)))

;;; ─── assess-probe ───

(define-test (decision-core assess-healthy)
  (let ((f (assess-probe :pass :clean :transport "ok" "ev-1")))
    (is eq :healthy (pf-status f))
    (is = 0 (pf-severity f))
    (is string= "ok" (pf-message f))
    (is string= "ev-1" (pf-evidence-ref f))))

(define-test (decision-core assess-unhealthy-auth)
  (let ((f (assess-probe :fail :clean :auth "auth failed" "ev-2")))
    (is eq :unhealthy (pf-status f))
    (is = 90 (pf-severity f))))

;;; ─── aggregate-severities ───

(define-test (decision-core aggregate-empty)
  (multiple-value-bind (mean max-s) (aggregate-severities '())
    (is = 0 mean)
    (is = 0 max-s)))

(define-test (decision-core aggregate-single)
  (let ((f (make-probe-finding :severity 50)))
    (multiple-value-bind (mean max-s) (aggregate-severities (list f))
      (is = 50 mean)
      (is = 50 max-s))))

(define-test (decision-core aggregate-multiple)
  (let ((fs (list (make-probe-finding :severity 20)
                  (make-probe-finding :severity 60)
                  (make-probe-finding :severity 40))))
    (multiple-value-bind (mean max-s) (aggregate-severities fs)
      (is = 40 mean)
      (is = 60 max-s))))

;;; ─── compute-verdict ───

(define-test (decision-core verdict-pass)
  (let ((th (make-severity-thresholds :pass-ceiling 20 :degraded-ceiling 60)))
    (is eq :pass (compute-verdict 15 15 th))))

(define-test (decision-core verdict-degraded)
  (let ((th (make-severity-thresholds :pass-ceiling 20 :degraded-ceiling 60)))
    (is eq :degraded (compute-verdict 40 40 th))))

(define-test (decision-core verdict-fail-by-score)
  (let ((th (make-severity-thresholds :pass-ceiling 20 :degraded-ceiling 60)))
    (is eq :fail (compute-verdict 70 70 th))))

(define-test (decision-core verdict-fail-by-max)
  (let ((th (make-severity-thresholds :pass-ceiling 20 :degraded-ceiling 60)))
    (is eq :fail (compute-verdict 10 85 th))))

(define-test (decision-core verdict-boundary-pass)
  (let ((th (make-severity-thresholds :pass-ceiling 20 :degraded-ceiling 60)))
    (is eq :pass (compute-verdict 20 20 th))))

(define-test (decision-core verdict-boundary-degraded)
  (let ((th (make-severity-thresholds :pass-ceiling 20 :degraded-ceiling 60)))
    (is eq :degraded (compute-verdict 60 60 th))))

;;; ─── run-decision-pipeline ───

(define-test (decision-core pipeline-all-healthy)
  (let* ((findings (list (assess-probe :pass :clean :transport "ok" "e1")
                         (assess-probe :pass :clean :conformance "ok" "e2")
                         (assess-probe :pass :clean :capability "ok" "e3")))
         (record (run-decision-pipeline findings :timestamp 1000)))
    (is eq :pass (dec-verdict record))
    (is = 3 (dec-finding-count record))
    (is = 1000 (rseed-timestamp (dec-replay-seed record)))))

(define-test (decision-core pipeline-mixed)
  (let* ((findings (list (assess-probe :pass :clean :transport "ok" "e1")
                         (assess-probe :pass :drifted :schema "drift" "e2")
                         (assess-probe :fail :clean :conformance "bad" "e3")))
         (record (run-decision-pipeline findings)))
    ;; Mean ~40 (0+45+75)/3, max 75 < 80 → :degraded
    (is eq :degraded (dec-verdict record))
    (is = 3 (dec-finding-count record))))

(define-test (decision-core pipeline-degraded)
  (let* ((findings (list (assess-probe :pass :clean :transport "ok" "e1")
                         (assess-probe :blocked-external :clean :auth "timeout" "e2")))
         (record (run-decision-pipeline findings)))
    (is eq :degraded (dec-verdict record))))

(define-test (decision-core pipeline-empty)
  (let ((record (run-decision-pipeline '())))
    (is eq :pass (dec-verdict record))
    (is = 0 (dec-aggregate-score record))))

;;; ─── verify-replay ───

(define-test (decision-core replay-matches)
  (let* ((findings (list (assess-probe :pass :clean :transport "ok" "e1")
                         (assess-probe :fail :clean :auth "fail" "e2")))
         (record (run-decision-pipeline findings :timestamp 5000)))
    (multiple-value-bind (match-p explanation)
        (verify-replay record findings)
      (is eq t match-p)
      (is string= "Replay matches original decision" explanation))))

(define-test (decision-core replay-mismatch)
  (let* ((findings (list (assess-probe :pass :clean :transport "ok" "e1")))
         (record (run-decision-pipeline findings :timestamp 5000))
         (different (list (assess-probe :fail :clean :auth "fail" "e2"))))
    (multiple-value-bind (match-p explanation)
        (verify-replay record different)
      (is eq nil match-p)
      (true (search "mismatch" explanation)))))

;;; ─── generate-reasoning ───

(define-test (decision-core reasoning-includes-verdict)
  (let ((r (generate-reasoning :pass 10 10 '())))
    (true (search "PASS" r))))

(define-test (decision-core reasoning-critical-domains)
  (let* ((findings (list (make-probe-finding :domain :auth :severity 70)))
         (r (generate-reasoning :fail 70 70 findings)))
    (true (search "AUTH" r))))

;;; ─── Custom thresholds ───

(define-test (decision-core custom-thresholds-strict)
  (let* ((th (make-severity-thresholds :pass-ceiling 5 :degraded-ceiling 15))
         (findings (list (assess-probe :pass :drifted :schema "drift" "e1")))
         (record (run-decision-pipeline findings :thresholds th)))
    ;; degraded schema with drift → severity ~45, well above strict thresholds
    (is eq :fail (dec-verdict record))))

(define-test (decision-core custom-thresholds-lenient)
  (let* ((th (make-severity-thresholds :pass-ceiling 50 :degraded-ceiling 80))
         (findings (list (assess-probe :pass :drifted :schema "drift" "e1")))
         (record (run-decision-pipeline findings :thresholds th)))
    (is eq :pass (dec-verdict record))))
