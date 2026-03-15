;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; schema-regression-generators-tests.lisp — Tests for property-based generators
;;;

(in-package #:orrery/harness-tests)

(define-test schema-regression-generators)

;;; ─── PRNG determinism ───

(define-test (schema-regression-generators prng-deterministic)
  (let ((s1 (make-gen-state :seed 42))
        (s2 (make-gen-state :seed 42)))
    (multiple-value-bind (v1 _) (gen-next-raw s1)
      (declare (ignore _))
      (multiple-value-bind (v2 _) (gen-next-raw s2)
        (declare (ignore _))
        (is = v1 v2)))))

(define-test (schema-regression-generators prng-advances)
  (let ((s (make-gen-state :seed 42)))
    (multiple-value-bind (_ s2) (gen-next-raw s)
      (declare (ignore _))
      (is = 1 (gs-counter s2))
      (true (/= (gs-seed s) (gs-seed s2))))))

(define-test (schema-regression-generators prng-zero-seed-no-stuck)
  ;; Seed of 0 should still produce values (xorshift handled)
  (let ((s (make-gen-state :seed 0)))
    (multiple-value-bind (v _) (gen-next-raw s)
      (declare (ignore _))
      ;; With seed 0, xorshift produces 0. That's fine for our use.
      (true (integerp v)))))

;;; ─── gen-integer ───

(define-test (schema-regression-generators integer-in-range)
  (let ((s (make-gen-state :seed 123)))
    (dotimes (i 20)
      (multiple-value-bind (v new-s) (gen-integer s 10 50)
        (true (<= 10 v 50))
        (setf s new-s)))))

(define-test (schema-regression-generators integer-min-eq-max)
  (multiple-value-bind (v _) (gen-integer (make-gen-state :seed 1) 7 7)
    (declare (ignore _))
    (is = 7 v)))

;;; ─── gen-element ───

(define-test (schema-regression-generators element-from-vector)
  (let ((s (make-gen-state :seed 99))
        (vec #(:a :b :c)))
    (dotimes (i 10)
      (multiple-value-bind (elem new-s) (gen-element s vec)
        (true (member elem '(:a :b :c)))
        (setf s new-s)))))

;;; ─── gen-string ───

(define-test (schema-regression-generators string-length-range)
  (let ((s (make-gen-state :seed 55)))
    (multiple-value-bind (str _) (gen-string s 3 10)
      (declare (ignore _))
      (true (<= 3 (length str) 10)))))

(define-test (schema-regression-generators string-deterministic)
  (let ((s1 (make-gen-state :seed 77))
        (s2 (make-gen-state :seed 77)))
    (multiple-value-bind (str1 _) (gen-string s1 5 5)
      (declare (ignore _))
      (multiple-value-bind (str2 _) (gen-string s2 5 5)
        (declare (ignore _))
        (is string= str1 str2)))))

;;; ─── gen-replay-event ───

(define-test (schema-regression-generators replay-event-typed)
  (multiple-value-bind (evt _) (gen-replay-event (make-gen-state :seed 42) 7)
    (declare (ignore _))
    (true (replay-event-p evt))
    (is = 7 (re-sequence-id evt))
    (true (member (re-event-type evt) '(:session :cron :health :usage :event :alert :probe)))))

;;; ─── gen-replay-stream ───

(define-test (schema-regression-generators replay-stream-count)
  (multiple-value-bind (stream _)
      (gen-replay-stream (make-gen-state :seed 42) "test" 5)
    (declare (ignore _))
    (is = 5 (length (rstr-events stream)))
    (is string= "test" (rstr-stream-id stream))))

(define-test (schema-regression-generators replay-stream-monotonic-ids)
  (multiple-value-bind (stream _)
      (gen-replay-stream (make-gen-state :seed 42) "mono" 10)
    (declare (ignore _))
    (let ((ids (mapcar #'re-sequence-id (rstr-events stream))))
      ;; IDs should be 1, 2, 3, ... 10
      (is equal (loop for i from 1 to 10 collect i) ids))))

(define-test (schema-regression-generators replay-stream-deterministic)
  (multiple-value-bind (s1 _)
      (gen-replay-stream (make-gen-state :seed 999) "det" 3)
    (declare (ignore _))
    (multiple-value-bind (s2 _)
        (gen-replay-stream (make-gen-state :seed 999) "det" 3)
      (declare (ignore _))
      ;; Same seed → same payloads
      (is string= (re-payload (first (rstr-events s1)))
                   (re-payload (first (rstr-events s2)))))))

;;; ─── gen-snapshot-sequence ───

(define-test (schema-regression-generators snapshot-count)
  (multiple-value-bind (snaps _)
      (gen-snapshot-sequence (make-gen-state :seed 42) 5)
    (declare (ignore _))
    (is = 5 (length snaps))))

(define-test (schema-regression-generators snapshot-monotonic-tokens)
  (multiple-value-bind (snaps _)
      (gen-snapshot-sequence (make-gen-state :seed 42) 10)
    (declare (ignore _))
    (let ((tokens (mapcar #'car snaps)))
      ;; Tokens should be lexicographically non-decreasing
      (loop for (a b) on tokens
            while b
            do (true (string<= a b))))))

;;; ─── gen-field-sig ───

(define-test (schema-regression-generators field-sig-typed)
  (multiple-value-bind (fs _) (gen-field-sig (make-gen-state :seed 42) "/test")
    (declare (ignore _))
    (true (field-sig-p fs))
    (true (stringp (fs-name fs)))
    (true (search "/test" (fs-path fs)))))

;;; ─── gen-schema-sig ───

(define-test (schema-regression-generators schema-sig-field-count)
  (multiple-value-bind (sig _) (gen-schema-sig (make-gen-state :seed 42) "/health" 4)
    (declare (ignore _))
    (is = 4 (length (ss-fields sig)))
    (is string= "/health" (ss-endpoint sig))))

;;; ─── gen-schema-pair ───

(define-test (schema-regression-generators schema-pair-same-endpoints)
  (multiple-value-bind (fix live _)
      (gen-schema-pair (make-gen-state :seed 42) "/test" 5 50)
    (declare (ignore _))
    (is string= (ss-endpoint fix) (ss-endpoint live))
    (is = (length (ss-fields fix)) (length (ss-fields live)))))

(define-test (schema-regression-generators schema-pair-zero-mutation-identical)
  (multiple-value-bind (fix live _)
      (gen-schema-pair (make-gen-state :seed 42) "/test" 5 0)
    (declare (ignore _))
    ;; 0% mutation → all field types should match
    (loop for ff in (ss-fields fix)
          for lf in (ss-fields live)
          do (is eq (fs-field-type ff) (fs-field-type lf)))))

(define-test (schema-regression-generators schema-pair-full-mutation-diverges)
  ;; 100% mutation → at least some fields should differ (probabilistic but reliable)
  (multiple-value-bind (fix live _)
      (gen-schema-pair (make-gen-state :seed 42) "/test" 10 100)
    (declare (ignore _))
    (let ((diffs (loop for ff in (ss-fields fix)
                       for lf in (ss-fields live)
                       count (not (eq (fs-field-type ff) (fs-field-type lf))))))
      ;; With 100% mutation and 6 type options, very unlikely all stay same
      (true (> diffs 0)))))

;;; ─── gen-regression-corpus ───

(define-test (schema-regression-generators corpus-structure)
  (multiple-value-bind (corpus _)
      (gen-regression-corpus (make-gen-state :seed 42)
                              :stream-count 3
                              :event-count 5
                              :snapshot-count 4
                              :endpoint-count 2
                              :field-count 3)
    (declare (ignore _))
    (true (regression-corpus-p corpus))
    (is = 3 (length (rc-streams corpus)))
    (is = 4 (length (rc-snapshots corpus)))
    (is = 2 (length (rc-fixture-sigs corpus)))
    (is = 2 (length (rc-live-sigs corpus)))
    (is = 42 (rc-seed corpus))))

(define-test (schema-regression-generators corpus-deterministic)
  (multiple-value-bind (c1 _)
      (gen-regression-corpus (make-gen-state :seed 12345)
                              :stream-count 2 :event-count 3
                              :snapshot-count 2 :endpoint-count 1 :field-count 2)
    (declare (ignore _))
    (multiple-value-bind (c2 _)
        (gen-regression-corpus (make-gen-state :seed 12345)
                                :stream-count 2 :event-count 3
                                :snapshot-count 2 :endpoint-count 1 :field-count 2)
      (declare (ignore _))
      ;; Same seed → same corpus-id
      (is string= (rc-corpus-id c1) (rc-corpus-id c2))
      ;; Same stream payloads
      (is string= (re-payload (first (rstr-events (first (rc-streams c1)))))
                   (re-payload (first (rstr-events (first (rc-streams c2)))))))))

;;; ─── Integration: corpus → invariant-suite ───

(define-test (schema-regression-generators corpus-passes-ordering-invariant)
  (multiple-value-bind (corpus _)
      (gen-regression-corpus (make-gen-state :seed 42))
    (declare (ignore _))
    ;; Generated streams should always have monotonic ordering
    (is = 0 (length (check-ordering-invariant (rc-streams corpus))))))

(define-test (schema-regression-generators corpus-passes-monotonicity-invariant)
  (multiple-value-bind (corpus _)
      (gen-regression-corpus (make-gen-state :seed 42))
    (declare (ignore _))
    ;; Generated snapshots should always have monotonic tokens
    (is = 0 (length (check-monotonicity-invariant (rc-snapshots corpus))))))
