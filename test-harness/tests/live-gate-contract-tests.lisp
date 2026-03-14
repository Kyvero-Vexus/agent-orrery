;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; live-gate-contract-tests.lisp — Contract tests against fixture corpus
;;;
;;; Validates classifier + remediation mapping for every fixture in the corpus.

(in-package #:orrery/harness-tests)

(define-test live-gate-contract-tests)

;;; Contract 1: classify-response-family agrees with fixture expected family
(define-test (live-gate-contract-tests family-classification-contract)
  (dolist (fix *live-gate-fixtures*)
    (let* ((ec (orrery/adapter/openclaw:make-endpoint-classification
                :path (format nil "/~A" (gf-name fix))
                :surface (gf-expected-surface fix)
                :http-status (gf-http-status fix)
                :content-type (gf-content-type fix)
                :body-shape (cond ((string= "" (gf-body fix)) :empty)
                                  ((and (plusp (length (gf-body fix)))
                                        (char= #\{ (char (gf-body fix) 0)))
                                   :json-object)
                                  ((and (plusp (length (gf-body fix)))
                                        (char= #\[ (char (gf-body fix) 0)))
                                   :json-array)
                                  ((search "<!DOCTYPE" (gf-body fix) :test #'char-equal)
                                   :html)
                                  ((search "<html" (gf-body fix) :test #'char-equal)
                                   :html)
                                  (t :other))
                :confidence 0.9))
           (family (orrery/adapter/openclaw:classify-response-family
                    ec (gf-http-status fix))))
      (is eq (gf-family fix) family
          "Fixture ~A: expected ~A got ~A" (gf-name fix) (gf-family fix) family))))

;;; Contract 2: remediation problem matches expected-problem for non-ready fixtures
(define-test (live-gate-contract-tests remediation-problem-contract)
  (dolist (fix *live-gate-fixtures*)
    (when (gf-expected-problem fix)
      (let ((hint (orrery/adapter/openclaw:make-family-remediation
                   (gf-family fix) (format nil "http://test/~A" (gf-name fix)))))
        (is eq (gf-expected-problem fix)
            (orrery/adapter/openclaw:rh-problem hint)
            "Fixture ~A: expected problem ~A got ~A"
            (gf-name fix) (gf-expected-problem fix)
            (orrery/adapter/openclaw:rh-problem hint))))))

;;; Contract 3: ready-p classification matches expected
(define-test (live-gate-contract-tests readiness-contract)
  (dolist (fix *live-gate-fixtures*)
    (let* ((ec (orrery/adapter/openclaw:make-endpoint-classification
                :path (format nil "/~A" (gf-name fix))
                :surface (gf-expected-surface fix)
                :http-status (gf-http-status fix)
                :content-type (gf-content-type fix)
                :body-shape :other :confidence 0.9))
           (family (orrery/adapter/openclaw:classify-response-family
                    ec (gf-http-status fix)))
           (ready (eq family :openclaw-api)))
      (is eq (gf-expected-ready-p fix) ready
          "Fixture ~A: expected ready=~A got ~A"
          (gf-name fix) (gf-expected-ready-p fix) ready))))

;;; Contract 4: all remediation hints have non-empty suggestion
(define-test (live-gate-contract-tests remediation-suggestion-non-empty)
  (dolist (fix *live-gate-fixtures*)
    (when (gf-expected-problem fix)
      (let ((hint (orrery/adapter/openclaw:make-family-remediation
                   (gf-family fix) "http://test/endpoint")))
        (true (plusp (length (orrery/adapter/openclaw:rh-suggestion hint)))
              "Fixture ~A: suggestion must be non-empty" (gf-name fix))))))

;;; Contract 5: corpus completeness — at least 2 fixtures per family
(define-test (live-gate-contract-tests corpus-completeness)
  (dolist (fam '(:openclaw-api :html-control-plane :auth-gated :unreachable :unknown))
    (let ((count (count fam *live-gate-fixtures* :key #'gf-family)))
      (true (>= count 2)
            "Family ~A: need >=2 fixtures, have ~D" fam count))))

;;; Contract 6: fixture struct fields non-nil
(define-test (live-gate-contract-tests fixture-field-integrity)
  (dolist (fix *live-gate-fixtures*)
    (true (plusp (length (gf-name fix)))
          "Fixture name must be non-empty")
    (true (gate-fixture-p fix)
          "Must be gate-fixture struct")))
