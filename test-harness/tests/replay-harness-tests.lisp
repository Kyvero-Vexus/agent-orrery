;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; replay-harness-tests.lisp — Tests for deterministic replay harness
;;;

(in-package #:orrery/harness-tests)

(define-test replay-harness)

;;; ─── Helpers ───

(defun make-test-event (seq-id etype payload &optional (ts 0))
  (make-replay-event :sequence-id seq-id :event-type etype :payload payload :timestamp ts))

(defun make-test-stream (id events &key (source :fixture) (seed 42))
  (make-replay-stream :stream-id id :source source :events events :seed seed))

;;; ─── validate-ordering ───

(define-test (replay-harness ordering-empty)
  (multiple-value-bind (ok msg) (validate-ordering '())
    (true ok)
    (true (search "valid" msg))))

(define-test (replay-harness ordering-single)
  (let ((events (list (make-test-event 1 :session "s1"))))
    (multiple-value-bind (ok _) (validate-ordering events)
      (declare (ignore _))
      (true ok))))

(define-test (replay-harness ordering-valid)
  (let ((events (list (make-test-event 1 :session "s1")
                      (make-test-event 2 :health "h1")
                      (make-test-event 3 :event "e1"))))
    (multiple-value-bind (ok _) (validate-ordering events)
      (declare (ignore _))
      (true ok))))

(define-test (replay-harness ordering-invalid)
  (let ((events (list (make-test-event 3 :session "s1")
                      (make-test-event 2 :health "h1"))))
    (multiple-value-bind (ok msg) (validate-ordering events)
      (false ok)
      (true (search "Non-monotonic" msg)))))

(define-test (replay-harness ordering-duplicate-ids)
  (let ((events (list (make-test-event 1 :session "s1")
                      (make-test-event 1 :health "h1"))))
    (multiple-value-bind (ok _) (validate-ordering events)
      (declare (ignore _))
      (false ok))))

;;; ─── event-to-finding ───

(define-test (replay-harness finding-session-maps-runtime)
  (let* ((ev (make-test-event 1 :session "data"))
         (f (event-to-finding ev)))
    (is eq :runtime (pf-domain f))
    (is eq :healthy (pf-status f))
    (is = 0 (pf-severity f))))

(define-test (replay-harness finding-empty-payload-unknown)
  (let* ((ev (make-test-event 1 :event ""))
         (f (event-to-finding ev)))
    (is eq :unknown (pf-status f))
    (is = 50 (pf-severity f))))

(define-test (replay-harness finding-probe-maps-schema)
  (let* ((ev (make-test-event 1 :probe "schema-check"))
         (f (event-to-finding ev)))
    (is eq :schema (pf-domain f))))

(define-test (replay-harness finding-alert-maps-auth)
  (let* ((ev (make-test-event 1 :alert "alert-data"))
         (f (event-to-finding ev)))
    (is eq :auth (pf-domain f))))

(define-test (replay-harness finding-evidence-ref-format)
  (let* ((ev (make-test-event 42 :health "ok"))
         (f (event-to-finding ev)))
    (true (search "replay:42" (pf-evidence-ref f)))))

;;; ─── replay-to-decision ───

(define-test (replay-harness decision-all-healthy-events)
  (let* ((events (list (make-test-event 1 :session "data")
                       (make-test-event 2 :health "ok")
                       (make-test-event 3 :event "evt")))
         (stream (make-test-stream "test-1" events))
         (decision (replay-to-decision stream)))
    (is eq :pass (dec-verdict decision))
    (is = 3 (dec-finding-count decision))))

(define-test (replay-harness decision-with-empty-payloads)
  (let* ((events (list (make-test-event 1 :session "")
                       (make-test-event 2 :event "")))
         (stream (make-test-stream "test-2" events))
         (decision (replay-to-decision stream)))
    ;; Empty payloads → :unknown status → severity 50
    (is eq :degraded (dec-verdict decision))))

(define-test (replay-harness decision-seed-preserved)
  (let* ((events (list (make-test-event 1 :session "data")))
         (stream (make-test-stream "test-3" events :seed 12345))
         (decision (replay-to-decision stream)))
    (is = 12345 (rseed-timestamp (dec-replay-seed decision)))))

;;; ─── diff-decisions ───

(define-test (replay-harness diff-identical)
  (let* ((findings (list (make-probe-finding :severity 10 :domain :transport)))
         (d1 (run-decision-pipeline findings :timestamp 1))
         (d2 (run-decision-pipeline findings :timestamp 1)))
    (is = 0 (length (diff-decisions d1 d2 0)))))

(define-test (replay-harness diff-verdict-mismatch)
  (let* ((f1 (list (make-probe-finding :severity 10 :domain :transport)))
         (f2 (list (make-probe-finding :severity 90 :domain :auth)))
         (d1 (run-decision-pipeline f1))
         (d2 (run-decision-pipeline f2)))
    (let ((diffs (diff-decisions d1 d2 0)))
      (true (find :verdict-mismatch diffs :key #'rd-diff-kind)))))

(define-test (replay-harness diff-score-mismatch)
  (let* ((f1 (list (make-probe-finding :severity 10 :domain :transport)))
         (f2 (list (make-probe-finding :severity 20 :domain :transport)))
         (d1 (run-decision-pipeline f1))
         (d2 (run-decision-pipeline f2)))
    (let ((diffs (diff-decisions d1 d2 0)))
      (true (find :score-mismatch diffs :key #'rd-diff-kind)))))

;;; ─── run-replay ───

(define-test (replay-harness replay-matching)
  (let* ((events (list (make-test-event 1 :session "data")
                       (make-test-event 2 :health "ok")))
         (stream (make-test-stream "rpl-1" events :seed 100))
         (original (replay-to-decision stream))
         (result (run-replay stream original)))
    (true (rpt-match-p result))
    (is = 0 (rpt-diff-count result))
    (is string= "rpl-1" (rpt-stream-id result))))

(define-test (replay-harness replay-mismatching)
  (let* ((events1 (list (make-test-event 1 :session "data")))
         (events2 (list (make-test-event 1 :event "")))
         (stream1 (make-test-stream "rpl-2" events1))
         (stream2 (make-test-stream "rpl-2" events2))
         (original (replay-to-decision stream1))
         (result (run-replay stream2 original)))
    (false (rpt-match-p result))
    (true (> (rpt-diff-count result) 0))))

;;; ─── run-batch-replay ───

(define-test (replay-harness batch-all-match)
  (let* ((e1 (list (make-test-event 1 :session "s")))
         (e2 (list (make-test-event 1 :health "h")))
         (s1 (make-test-stream "b1" e1))
         (s2 (make-test-stream "b2" e2))
         (d1 (replay-to-decision s1))
         (d2 (replay-to-decision s2))
         (results (run-batch-replay (list s1 s2) (list d1 d2))))
    (is = 2 (length results))
    (true (every #'rpt-match-p results))))

(define-test (replay-harness batch-partial-match)
  (let* ((e1 (list (make-test-event 1 :session "s")))
         (e2-orig (list (make-test-event 1 :health "h")))
         (e2-replay (list (make-test-event 1 :event "")))
         (s1 (make-test-stream "b1" e1))
         (s2-orig (make-test-stream "b2" e2-orig))
         (s2-replay (make-test-stream "b2" e2-replay))
         (d1 (replay-to-decision s1))
         (d2 (replay-to-decision s2-orig))
         (results (run-batch-replay (list s1 s2-replay) (list d1 d2))))
    (true (rpt-match-p (first results)))
    (false (rpt-match-p (second results)))))

;;; ─── Determinism invariant ───

(define-test (replay-harness determinism-same-seed-same-result)
  (let* ((events (list (make-test-event 1 :session "x")
                       (make-test-event 2 :alert "y")
                       (make-test-event 3 :probe "z")))
         (s1 (make-test-stream "det" events :seed 999))
         (s2 (make-test-stream "det" events :seed 999))
         (d1 (replay-to-decision s1))
         (d2 (replay-to-decision s2)))
    (is eq (dec-verdict d1) (dec-verdict d2))
    (is = (dec-aggregate-score d1) (dec-aggregate-score d2))
    (is = (dec-max-severity d1) (dec-max-severity d2))))
