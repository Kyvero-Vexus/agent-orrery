;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; decision-audit-tests.lisp — Tests for gate decision audit log
;;;

(in-package #:orrery/harness-tests)

(define-test decision-audit)

;;; ─── Helpers ───

(defun make-test-dec (verdict score &key (finding-count 0))
  (make-decision-record :verdict verdict :aggregate-score score
                        :finding-count finding-count :findings '()))

;;; ─── Entry from Decision ───

(define-test (decision-audit entry-from-decision)
  (let* ((rec (make-test-dec :pass 10))
         (entry (make-audit-entry-from-decision rec :gate-id "g1"
                                                     :context "test"
                                                     :timestamp 5000)))
    (is eq :pass (aue-verdict entry))
    (is = 10 (aue-aggregate-score entry))
    (is string= "g1" (aue-gate-id entry))
    (is = 5000 (aue-timestamp entry))))

;;; ─── Append ───

(define-test (decision-audit append-single)
  (let* ((log (make-audit-log :log-id "test-log"))
         (entry (make-audit-entry :entry-id "e1" :verdict :pass :timestamp 1000))
         (new-log (append-to-audit-log log entry)))
    (is = 1 (al-entry-count new-log))
    (is = 1 (al-pass-count new-log))
    (is = 1000 (al-first-timestamp new-log))))

(define-test (decision-audit append-multiple)
  (let* ((log (make-audit-log :log-id "test"))
         (e1 (make-audit-entry :entry-id "e1" :verdict :pass :timestamp 1000))
         (e2 (make-audit-entry :entry-id "e2" :verdict :fail :timestamp 2000))
         (log2 (append-to-audit-log (append-to-audit-log log e1) e2)))
    (is = 2 (al-entry-count log2))
    (is = 1 (al-pass-count log2))
    (is = 1 (al-fail-count log2))))

(define-test (decision-audit append-immutable)
  (let* ((log (make-audit-log :log-id "orig"))
         (entry (make-audit-entry :entry-id "e1" :verdict :pass :timestamp 1000))
         (new-log (append-to-audit-log log entry)))
    (is = 0 (al-entry-count log))
    (is = 1 (al-entry-count new-log))))

;;; ─── Build Log ───

(define-test (decision-audit build-empty)
  (let ((log (build-audit-log '() :log-id "empty")))
    (is = 0 (al-entry-count log))))

(define-test (decision-audit build-from-records)
  (let* ((r1 (make-test-dec :pass 5))
         (r2 (make-test-dec :fail 80 :finding-count 3))
         (log (build-audit-log (list r1 r2) :log-id "ordered")))
    (is = 2 (al-entry-count log))
    (is = 1 (al-pass-count log))
    (is = 1 (al-fail-count log))))

;;; ─── Diff ───

(define-test (decision-audit diff-identical)
  (let* ((e1 (make-audit-entry :entry-id "e1" :verdict :pass :timestamp 1000))
         (log1 (append-to-audit-log (make-audit-log :log-id "a") e1))
         (log2 (append-to-audit-log (make-audit-log :log-id "b") e1))
         (diff (diff-audit-logs log1 log2)))
    (is = 0 (ad-added-count diff))
    (is = 0 (ad-removed-count diff))
    (is = 0 (ad-changed-count diff))
    (false (ad-regressions-p diff))))

(define-test (decision-audit diff-added)
  (let* ((e1 (make-audit-entry :entry-id "e1" :verdict :pass :timestamp 1000))
         (e2 (make-audit-entry :entry-id "e2" :verdict :pass :timestamp 2000))
         (log1 (append-to-audit-log (make-audit-log :log-id "a") e1))
         (log2 (append-to-audit-log (append-to-audit-log (make-audit-log :log-id "b") e1) e2))
         (diff (diff-audit-logs log1 log2)))
    (is = 1 (ad-added-count diff))
    (false (ad-regressions-p diff))))

(define-test (decision-audit diff-removed)
  (let* ((e1 (make-audit-entry :entry-id "e1" :verdict :pass :timestamp 1000))
         (e2 (make-audit-entry :entry-id "e2" :verdict :pass :timestamp 2000))
         (log1 (append-to-audit-log (append-to-audit-log (make-audit-log :log-id "a") e1) e2))
         (log2 (append-to-audit-log (make-audit-log :log-id "b") e1))
         (diff (diff-audit-logs log1 log2)))
    (is = 1 (ad-removed-count diff))))

(define-test (decision-audit diff-regression)
  (let* ((e1-pass (make-audit-entry :entry-id "e1" :verdict :pass :timestamp 1000))
         (e1-fail (make-audit-entry :entry-id "e1" :verdict :fail :timestamp 1000))
         (log1 (append-to-audit-log (make-audit-log :log-id "a") e1-pass))
         (log2 (append-to-audit-log (make-audit-log :log-id "b") e1-fail))
         (diff (diff-audit-logs log1 log2)))
    (is = 1 (ad-changed-count diff))
    (true (ad-regressions-p diff))))

;;; ─── JSON ───

(define-test (decision-audit entry-json)
  (let* ((entry (make-audit-entry :entry-id "e1" :verdict :pass
                                  :aggregate-score 10 :timestamp 1000))
         (json (audit-entry-to-json entry)))
    (true (search "entry_id" json))
    (true (search "e1" json))))

(define-test (decision-audit log-json)
  (let* ((e1 (make-audit-entry :entry-id "e1" :verdict :pass :timestamp 1000))
         (log (append-to-audit-log (make-audit-log :log-id "json-test") e1))
         (json (audit-log-to-json log)))
    (true (search "log_id" json))
    (true (search "json-test" json))
    (true (search "entries" json))))

(define-test (decision-audit diff-json)
  (let* ((log1 (make-audit-log :log-id "a"))
         (log2 (make-audit-log :log-id "b"))
         (diff (diff-audit-logs log1 log2 :diff-id "d1"))
         (json (audit-diff-to-json diff)))
    (true (search "diff_id" json))
    (true (search "d1" json))
    (true (search "regressions" json))))

;;; ─── Integration ───

(define-test (decision-audit full-cycle)
  (let* ((e1 (make-audit-entry :entry-id "v1" :verdict :pass :aggregate-score 5 :timestamp 1000))
         (e2 (make-audit-entry :entry-id "v2" :verdict :pass :aggregate-score 10 :timestamp 2000))
         (e3 (make-audit-entry :entry-id "v3" :verdict :fail :aggregate-score 75 :finding-count 2 :timestamp 3000))
         (log (reduce #'append-to-audit-log (list e1 e2 e3)
                      :initial-value (make-audit-log :log-id "cycle")))
         (json (audit-log-to-json log)))
    (is = 3 (al-entry-count log))
    (is = 2 (al-pass-count log))
    (is = 1 (al-fail-count log))
    (true (> (length json) 100))))
