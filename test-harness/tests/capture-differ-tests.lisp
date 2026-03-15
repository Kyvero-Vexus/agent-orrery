;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test capture-differ)

(defun %sample (ep status body latency)
  (make-endpoint-sample :endpoint ep :status-code status :body body :latency-ms latency :timestamp 0 :error-p nil))

(defun %cap (&rest samples)
  (make-capture-result :snapshots samples :artifacts '() :diagnostics '() :success-p t))

(define-test (capture-differ endpoint-identical)
  (let* ((a (%sample "/api/v1/sessions" 200 "{}" 10))
         (d (diff-endpoint-samples a a)))
    (is eq :identical (ed-classification d))))

(define-test (capture-differ endpoint-regressed)
  (let* ((a (%sample "/api/v1/health" 200 "{}" 10))
         (b (%sample "/api/v1/health" 500 "{}" 20))
         (d (diff-endpoint-samples a b)))
    (is eq :regressed (ed-classification d))))

(define-test (capture-differ endpoint-improved)
  (let* ((a (%sample "/api/v1/health" 500 "{}" 20))
         (b (%sample "/api/v1/health" 200 "{}" 10))
         (d (diff-endpoint-samples a b)))
    (is eq :improved (ed-classification d))))

(define-test (capture-differ result-diff-basic)
  (let* ((before (%cap (%sample "/a" 200 "x" 10)
                       (%sample "/b" 200 "y" 15)))
         (after (%cap (%sample "/a" 200 "x" 12)
                      (%sample "/b" 500 "y" 15)
                      (%sample "/c" 200 "z" 8)))
         (diff (diff-capture-results before after :diff-id "d1")))
    (is string= "d1" (cd-diff-id diff))
    (is = 3 (cd-endpoint-count diff))
    (is = 1 (cd-regressed-count diff))
    (is = 1 (cd-new-count diff))
    (true (cd-regressions-p diff))))

(define-test (capture-differ removed-endpoint)
  (let* ((before (%cap (%sample "/a" 200 "x" 10)
                       (%sample "/b" 200 "y" 15)))
         (after (%cap (%sample "/a" 200 "x" 10)))
         (diff (diff-capture-results before after)))
    (is = 1 (cd-removed-count diff))))

(define-test (capture-differ json)
  (let* ((before (%cap (%sample "/a" 200 "x" 10)))
         (after (%cap (%sample "/a" 200 "x" 10)))
         (diff (diff-capture-results before after :diff-id "j1"))
         (json (capture-diff-to-json diff)))
    (true (search "diff_id" json))
    (true (search "j1" json))))
