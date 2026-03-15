;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-invariant-checker-tests.lisp — Tests for gate invariant checker
;;;

(in-package #:orrery/harness-tests)

(define-test gate-invariant-checker)

;;; ─── Helpers ───

(defun make-iv-event (seq-id etype payload &optional (ts 0))
  (make-replay-event :sequence-id seq-id :event-type etype :payload payload :timestamp ts))

(defun make-iv-stream (id events &key (source :fixture) (seed 42))
  (make-replay-stream :stream-id id :source source :events events :seed seed))

(defun make-token-snapshot (token)
  "Make a simple (cons token label) snapshot for monotonicity tests."
  (cons token "test"))

;;; ─── check-ordering-invariant ───

(define-test (gate-invariant-checker ordering-empty)
  (is = 0 (length (check-ordering-invariant '()))))

(define-test (gate-invariant-checker ordering-valid-streams)
  (let* ((e1 (list (make-iv-event 1 :session "s") (make-iv-event 2 :health "h")))
         (e2 (list (make-iv-event 1 :event "e") (make-iv-event 3 :probe "p")))
         (streams (list (make-iv-stream "s1" e1) (make-iv-stream "s2" e2))))
    (is = 0 (length (check-ordering-invariant streams)))))

(define-test (gate-invariant-checker ordering-one-invalid)
  (let* ((good (list (make-iv-event 1 :session "s") (make-iv-event 2 :health "h")))
         (bad (list (make-iv-event 5 :event "e") (make-iv-event 2 :probe "p")))
         (streams (list (make-iv-stream "good" good) (make-iv-stream "bad" bad))))
    (let ((vs (check-ordering-invariant streams)))
      (is = 1 (length vs))
      (is eq :ordering (iv-invariant-class (first vs)))
      (is eq :fatal (iv-severity (first vs)))
      (true (search "bad" (iv-artifact-ref (first vs)))))))

(define-test (gate-invariant-checker ordering-duplicate-ids)
  (let* ((events (list (make-iv-event 1 :session "s") (make-iv-event 1 :health "h")))
         (streams (list (make-iv-stream "dup" events))))
    (is = 1 (length (check-ordering-invariant streams)))))

;;; ─── check-monotonicity-invariant ───

(define-test (gate-invariant-checker monotonicity-empty)
  (is = 0 (length (check-monotonicity-invariant '()))))

(define-test (gate-invariant-checker monotonicity-single)
  (is = 0 (length (check-monotonicity-invariant (list (make-token-snapshot "abc"))))))

(define-test (gate-invariant-checker monotonicity-ascending)
  (let ((snaps (list (make-token-snapshot "aaa")
                     (make-token-snapshot "bbb")
                     (make-token-snapshot "ccc"))))
    (is = 0 (length (check-monotonicity-invariant snaps)))))

(define-test (gate-invariant-checker monotonicity-decreasing)
  (let ((snaps (list (make-token-snapshot "zzz")
                     (make-token-snapshot "aaa"))))
    (let ((vs (check-monotonicity-invariant snaps)))
      (is = 1 (length vs))
      (is eq :monotonicity (iv-invariant-class (first vs)))
      (is eq :error (iv-severity (first vs))))))

(define-test (gate-invariant-checker monotonicity-empty-tokens-skip)
  (let ((snaps (list (make-token-snapshot "aaa")
                     (make-token-snapshot "")
                     (make-token-snapshot "bbb"))))
    (is = 0 (length (check-monotonicity-invariant snaps)))))

(define-test (gate-invariant-checker monotonicity-equal-tokens-ok)
  (let ((snaps (list (make-token-snapshot "same")
                     (make-token-snapshot "same"))))
    (is = 0 (length (check-monotonicity-invariant snaps)))))

;;; ─── check-determinism-invariant ───

(define-test (gate-invariant-checker determinism-consistent)
  (let* ((events (list (make-iv-event 1 :session "data")
                       (make-iv-event 2 :health "ok")))
         (stream (make-iv-stream "det" events :seed 100))
         (report (run-replay stream (replay-to-decision stream))))
    (is = 0 (length (check-determinism-invariant (list stream) (list report))))))

(define-test (gate-invariant-checker determinism-tampered-report)
  (let* ((events-orig (list (make-iv-event 1 :session "data")))
         (events-diff (list (make-iv-event 1 :event "")))
         (stream-orig (make-iv-stream "orig" events-orig))
         (stream-diff (make-iv-stream "diff" events-diff))
         ;; Generate report from different events
         (report (run-replay stream-diff (replay-to-decision stream-diff))))
    ;; Now check stream-orig against report from stream-diff — should mismatch
    (let ((vs (check-determinism-invariant (list stream-orig) (list report))))
      (is = 1 (length vs))
      (is eq :determinism (iv-invariant-class (first vs)))
      (is eq :fatal (iv-severity (first vs))))))

;;; ─── check-schema-contract-invariant ───

(define-test (gate-invariant-checker schema-all-info)
  (let ((reports (list (make-compat-report
                        :endpoint "/health"
                        :compatible-p t
                        :max-severity :info))))
    (is = 0 (length (check-schema-contract-invariant reports)))))

(define-test (gate-invariant-checker schema-degrading-warning)
  (let ((reports (list (make-compat-report
                        :endpoint "/sessions"
                        :compatible-p t
                        :mismatches (list (make-compat-mismatch
                                           :severity :degrading))
                        :max-severity :degrading))))
    (let ((vs (check-schema-contract-invariant reports)))
      (is = 1 (length vs))
      (is eq :warning (iv-severity (first vs))))))

(define-test (gate-invariant-checker schema-breaking-error)
  (let ((reports (list (make-compat-report
                        :endpoint "/events"
                        :compatible-p nil
                        :mismatches (list (make-compat-mismatch
                                           :severity :breaking)
                                          (make-compat-mismatch
                                           :severity :breaking))
                        :max-severity :breaking))))
    (let ((vs (check-schema-contract-invariant reports)))
      (is = 1 (length vs))
      (is eq :error (iv-severity (first vs)))
      (true (search "2 mismatches" (iv-description (first vs)))))))

;;; ─── has-fatal-violation-p ───

(define-test (gate-invariant-checker fatal-none)
  (false (has-fatal-violation-p '())))

(define-test (gate-invariant-checker fatal-has-warning-only)
  (false (has-fatal-violation-p
          (list (make-invariant-violation :severity :warning)))))

(define-test (gate-invariant-checker fatal-has-fatal)
  (true (has-fatal-violation-p
         (list (make-invariant-violation :severity :warning)
               (make-invariant-violation :severity :fatal)))))

;;; ─── run-invariant-suite ───

(define-test (gate-invariant-checker suite-all-pass)
  (let* ((events (list (make-iv-event 1 :session "data")
                       (make-iv-event 2 :health "ok")))
         (stream (make-iv-stream "suite" events :seed 50))
         (decision (replay-to-decision stream))
         (report (run-replay stream decision))
         (snaps (list (make-token-snapshot "a") (make-token-snapshot "b")))
         (compat (list (make-compat-report :endpoint "/h" :max-severity :info)))
         (result (run-invariant-suite
                  (list stream) snaps (list report) compat)))
    (true (ir-pass-p result))
    (is = 0 (ir-violation-count result))
    (true (> (ir-checked-count result) 0))
    (true (search "passed" (ir-summary result)))))

(define-test (gate-invariant-checker suite-mixed-violations)
  (let* ((bad-events (list (make-iv-event 5 :session "s") (make-iv-event 2 :health "h")))
         (stream (make-iv-stream "bad" bad-events))
         (decision (replay-to-decision stream))
         (report (run-replay stream decision))
         (snaps (list (make-token-snapshot "zzz") (make-token-snapshot "aaa")))
         (compat (list (make-compat-report :endpoint "/x"
                                            :compatible-p nil
                                            :mismatches (list (make-compat-mismatch
                                                               :severity :breaking))
                                            :max-severity :breaking)))
         (result (run-invariant-suite
                  (list stream) snaps (list report) compat)))
    (false (ir-pass-p result))
    (true (>= (ir-violation-count result) 3))  ; ordering + monotonicity + schema
    (true (search "violations" (ir-summary result)))))

(define-test (gate-invariant-checker suite-empty-inputs)
  (let ((result (run-invariant-suite '() '() '() '())))
    (true (ir-pass-p result))
    (is = 0 (ir-violation-count result))
    (is = 0 (ir-checked-count result))))
