;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; fixture-replay-compiler-tests.lisp

(in-package #:orrery/harness-tests)

(define-test fixture-replay-compiler)

(defun %mk-event (id msg ts)
  (orrery/domain:make-event-record
   :id id :kind :info :source "test" :message msg :timestamp ts :metadata nil))

(defun %mk-snapshot (events token)
  (orrery/pipeline:make-normalized-snapshot
   :sessions '()
   :events events
   :alerts '()
   :sync-token token))

(define-test (fixture-replay-compiler event-conversion)
  (let* ((ev (%mk-event "e1" "hello" 10))
         (re (normalize-event->replay-event ev 3)))
    (is = 3 (re-sequence-id re))
    (is eq :event (re-event-type re))
    (is string= "hello" (re-payload re))
    (is = 10 (re-timestamp re))))

(define-test (fixture-replay-compiler snapshot-events-sequencing)
  (let ((snap (%mk-snapshot (list (%mk-event "e1" "a" 1)
                                  (%mk-event "e2" "b" 2))
                            "tok-1")))
    (multiple-value-bind (events next)
        (snapshot->replay-events snap :start-sequence 7)
      (is = 2 (length events))
      (is = 7 (re-sequence-id (first events)))
      (is = 8 (re-sequence-id (second events)))
      (is = 9 next))))

(define-test (fixture-replay-compiler compile-basic)
  (let* ((s1 (%mk-snapshot (list (%mk-event "e1" "a" 1)
                                 (%mk-event "e2" "b" 2))
                           "tok-a"))
         (s2 (%mk-snapshot (list (%mk-event "e3" "c" 3)) "tok-b"))
         (bundle (compile-fixture-replay-bundle (list s1 s2)
                                                :bundle-id "qyn"
                                                :seed 42
                                                :timestamp 1000)))
    (is string= "qyn" (frb-bundle-id bundle))
    (is = 2 (frb-snapshot-count bundle))
    (is = 3 (frb-event-count bundle))
    (is = 2 (length (frb-streams bundle)))
    (is = 2 (length (frb-artifacts bundle)))
    (is = 2 (length (frb-fixture-corpus bundle)))
    (is = 1000 (frb-timestamp bundle))))

(define-test (fixture-replay-compiler deterministic-output)
  (let* ((s1 (%mk-snapshot (list (%mk-event "e1" "a" 1)) "tok-a"))
         (b1 (compile-fixture-replay-bundle (list s1)
                                            :bundle-id "det"
                                            :seed 9
                                            :timestamp 777))
         (b2 (compile-fixture-replay-bundle (list s1)
                                            :bundle-id "det"
                                            :seed 9
                                            :timestamp 777)))
    (is string= (rstr-stream-id (first (frb-streams b1)))
        (rstr-stream-id (first (frb-streams b2))))
    (is string= (first (frb-fixture-corpus b1))
        (first (frb-fixture-corpus b2)))
    (is string= (ae-checksum (first (frb-artifacts b1)))
        (ae-checksum (first (frb-artifacts b2))))))

(define-test (fixture-replay-compiler artifact-validation)
  (let* ((s1 (%mk-snapshot (list (%mk-event "e1" "payload" 1)) "tok-a"))
         (bundle (compile-fixture-replay-bundle (list s1)
                                                :bundle-id "val"
                                                :seed 1
                                                :timestamp 123))
         (stream (first (frb-streams bundle)))
         (artifact (first (frb-artifacts bundle)))
         (validated (run-artifact-validation artifact stream)))
    (true (ae-valid-p validated))
    (is = 0 (length (ae-errors validated)))))

(define-test (fixture-replay-compiler fixture-json-shape)
  (let* ((s1 (%mk-snapshot (list (%mk-event "e1" "payload" 1)) "tok-a"))
         (bundle (compile-fixture-replay-bundle (list s1)
                                                :bundle-id "json"
                                                :seed 1
                                                :timestamp 123))
         (line (first (frb-fixture-corpus bundle))))
    (true (search "stream_id" line))
    (true (search "event_count" line))
    (true (search "json-s0" line))))
