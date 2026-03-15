;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; fixture-replay-compiler-tests.lisp — Tests for deterministic fixture replay bundle compiler
;;;

(in-package #:orrery/harness-tests)

;;; ─── Helpers ───

(defun make-frc-domain-event (&key (id "ev-1") (kind :info) (source "test")
                                (message "hello") (timestamp 1000))
  (orrery/domain:make-event-record
   :id id :kind kind :source source :message message :timestamp timestamp))

(defun make-frc-snapshot (&key (events '()) (sync-token "tok-1"))
  (orrery/pipeline:make-normalized-snapshot
   :sessions '()
   :events events
   :alerts '()
   :sync-token sync-token))

;;; ─── Root suite ───

(define-test fixture-replay-compiler)

;;; ─── normalize-event->replay-event ───

(define-test (fixture-replay-compiler normalize-event-basic)
  (let* ((ev (make-frc-domain-event :message "ping" :timestamp 42))
         (re (normalize-event->replay-event ev 7)))
    (true (replay-event-p re))
    (is = 7 (re-sequence-id re))
    (is eq :event (re-event-type re))
    (is string= "ping" (re-payload re))
    (is = 42 (re-timestamp re))))

(define-test (fixture-replay-compiler normalize-event-preserves-message)
  (let* ((ev (make-frc-domain-event :message "long payload with spaces"))
         (re (normalize-event->replay-event ev 0)))
    (is string= "long payload with spaces" (re-payload re))))

;;; ─── snapshot->replay-events ───

(define-test (fixture-replay-compiler snapshot-empty)
  (let ((snap (make-frc-snapshot :events '())))
    (multiple-value-bind (events next-seq)
        (snapshot->replay-events snap :start-sequence 0)
      (is = 0 (length events))
      (is = 0 next-seq))))

(define-test (fixture-replay-compiler snapshot-single-event)
  (let ((snap (make-frc-snapshot
               :events (list (make-frc-domain-event :message "e1" :timestamp 100)))))
    (multiple-value-bind (events next-seq)
        (snapshot->replay-events snap :start-sequence 5)
      (is = 1 (length events))
      (is = 6 next-seq)
      (is = 5 (re-sequence-id (first events)))
      (is string= "e1" (re-payload (first events))))))

(define-test (fixture-replay-compiler snapshot-multiple-monotonic-seq)
  (let ((snap (make-frc-snapshot
               :events (list (make-frc-domain-event :message "a" :timestamp 10)
                             (make-frc-domain-event :message "b" :timestamp 20)
                             (make-frc-domain-event :message "c" :timestamp 30)))))
    (multiple-value-bind (events next-seq)
        (snapshot->replay-events snap :start-sequence 0)
      (is = 3 (length events))
      (is = 3 next-seq)
      (is = 0 (re-sequence-id (first events)))
      (is = 1 (re-sequence-id (second events)))
      (is = 2 (re-sequence-id (third events))))))

(define-test (fixture-replay-compiler snapshot-start-sequence-offset)
  (let ((snap (make-frc-snapshot
               :events (list (make-frc-domain-event :message "x" :timestamp 1)
                             (make-frc-domain-event :message "y" :timestamp 2)))))
    (multiple-value-bind (events next-seq)
        (snapshot->replay-events snap :start-sequence 100)
      (is = 2 (length events))
      (is = 102 next-seq)
      (is = 100 (re-sequence-id (first events)))
      (is = 101 (re-sequence-id (second events))))))

;;; ─── replay-stream->artifact ───

(define-test (fixture-replay-compiler artifact-envelope-structure)
  (let* ((stream (make-replay-stream
                  :stream-id "test-s0"
                  :source :fixture
                  :events (list (make-replay-event :sequence-id 0 :payload "p"
                                                   :timestamp 100))
                  :seed 42
                  :metadata "tok"))
         (art (replay-stream->artifact stream 9999 :fixture)))
    (true (artifact-envelope-p art))
    (is string= "art-test-s0" (ae-artifact-id art))
    (is eq :replay-stream (ae-kind art))
    (is string= "1.0.0" (ae-version art))
    (is = 9999 (ae-created-at art))
    (is eq :fixture (ae-source art))
    (is = 1 (ae-payload-size art))
    (true (ae-valid-p art))
    (is = 0 (length (ae-errors art)))
    (true (> (length (ae-checksum art)) 0))))

(define-test (fixture-replay-compiler artifact-deterministic-checksum)
  (let* ((stream (make-replay-stream
                  :stream-id "det-s0" :source :fixture
                  :events (list (make-replay-event :sequence-id 0 :payload "x"
                                                   :timestamp 1))
                  :seed 7 :metadata ""))
         (a1 (replay-stream->artifact stream 100 :fixture))
         (a2 (replay-stream->artifact stream 100 :fixture)))
    (is string= (ae-checksum a1) (ae-checksum a2))))

(define-test (fixture-replay-compiler artifact-different-checksums)
  (let* ((s1 (make-replay-stream :stream-id "a" :source :fixture
                                 :events (list (make-replay-event :sequence-id 0
                                                                  :payload "p" :timestamp 1))
                                 :seed 1 :metadata ""))
         (s2 (make-replay-stream :stream-id "b" :source :fixture
                                 :events (list (make-replay-event :sequence-id 0
                                                                  :payload "p" :timestamp 1))
                                 :seed 1 :metadata ""))
         (a1 (replay-stream->artifact s1 100 :fixture))
         (a2 (replay-stream->artifact s2 100 :fixture)))
    (false (string= (ae-checksum a1) (ae-checksum a2)))))

;;; ─── replay-stream->fixture-json ───

(define-test (fixture-replay-compiler fixture-json-format)
  (let* ((stream (make-replay-stream
                  :stream-id "fj-s0" :source :fixture
                  :events (list (make-replay-event :sequence-id 0 :payload "a" :timestamp 1)
                                (make-replay-event :sequence-id 1 :payload "b" :timestamp 2))
                  :seed 99 :metadata ""))
         (json (replay-stream->fixture-json stream)))
    (true (stringp json))
    (true (search "\"fj-s0\"" json))
    (true (search "\"event_count\":2" json))
    (true (search "\"seed\":99" json))))

;;; ─── compile-fixture-replay-bundle ───

(define-test (fixture-replay-compiler compile-empty-snapshots)
  (let ((bundle (compile-fixture-replay-bundle '()
                                               :bundle-id "empty"
                                               :seed 0
                                               :source :fixture
                                               :timestamp 1000)))
    (true (fixture-replay-bundle-p bundle))
    (is string= "empty" (frb-bundle-id bundle))
    (is eq :fixture (frb-source bundle))
    (is = 0 (length (frb-streams bundle)))
    (is = 0 (length (frb-artifacts bundle)))
    (is = 0 (length (frb-fixture-corpus bundle)))
    (is = 0 (frb-event-count bundle))
    (is = 0 (frb-snapshot-count bundle))
    (is = 1000 (frb-timestamp bundle))))

(define-test (fixture-replay-compiler compile-single-snapshot)
  (let* ((snap (make-frc-snapshot
                :events (list (make-frc-domain-event :message "ev1" :timestamp 10)
                              (make-frc-domain-event :message "ev2" :timestamp 20))
                :sync-token "sync-1"))
         (bundle (compile-fixture-replay-bundle (list snap)
                                                :bundle-id "b1"
                                                :seed 100
                                                :source :fixture
                                                :timestamp 5000)))
    (is = 1 (length (frb-streams bundle)))
    (is = 1 (length (frb-artifacts bundle)))
    (is = 1 (length (frb-fixture-corpus bundle)))
    (is = 2 (frb-event-count bundle))
    (is = 1 (frb-snapshot-count bundle))
    (let ((stream (first (frb-streams bundle))))
      (is string= "b1-s0" (rstr-stream-id stream))
      (is eq :fixture (rstr-source stream))
      (is = 100 (rstr-seed stream))
      (is = 2 (length (rstr-events stream)))
      (is = 0 (re-sequence-id (first (rstr-events stream))))
      (is = 1 (re-sequence-id (second (rstr-events stream)))))))

(define-test (fixture-replay-compiler compile-multiple-snapshots)
  (let* ((snap1 (make-frc-snapshot
                 :events (list (make-frc-domain-event :message "a" :timestamp 1)
                               (make-frc-domain-event :message "b" :timestamp 2))
                 :sync-token "tok-1"))
         (snap2 (make-frc-snapshot
                 :events (list (make-frc-domain-event :message "c" :timestamp 3))
                 :sync-token "tok-2"))
         (snap3 (make-frc-snapshot
                 :events (list (make-frc-domain-event :message "d" :timestamp 4)
                               (make-frc-domain-event :message "e" :timestamp 5)
                               (make-frc-domain-event :message "f" :timestamp 6))
                 :sync-token "tok-3"))
         (bundle (compile-fixture-replay-bundle (list snap1 snap2 snap3)
                                                :bundle-id "multi"
                                                :seed 0
                                                :source :fixture
                                                :timestamp 9999)))
    (is = 3 (length (frb-streams bundle)))
    (is = 3 (length (frb-artifacts bundle)))
    (is = 3 (length (frb-fixture-corpus bundle)))
    (is = 6 (frb-event-count bundle))
    (is = 3 (frb-snapshot-count bundle))
    ;; Stream IDs follow bundle-id-sN pattern
    (is string= "multi-s0" (rstr-stream-id (first (frb-streams bundle))))
    (is string= "multi-s1" (rstr-stream-id (second (frb-streams bundle))))
    (is string= "multi-s2" (rstr-stream-id (third (frb-streams bundle))))
    ;; Seeds increment from base
    (is = 0 (rstr-seed (first (frb-streams bundle))))
    (is = 1 (rstr-seed (second (frb-streams bundle))))
    (is = 2 (rstr-seed (third (frb-streams bundle))))
    ;; Sequence IDs are monotonic ACROSS snapshots
    (let ((all-events (append (rstr-events (first (frb-streams bundle)))
                              (rstr-events (second (frb-streams bundle)))
                              (rstr-events (third (frb-streams bundle))))))
      (is = 6 (length all-events))
      (loop for i from 0 below 6
            do (is = i (re-sequence-id (nth i all-events)))))))

(define-test (fixture-replay-compiler compile-deterministic)
  (let* ((snap (make-frc-snapshot
                :events (list (make-frc-domain-event :message "det" :timestamp 42))
                :sync-token "tok"))
         (b1 (compile-fixture-replay-bundle (list snap)
                                            :bundle-id "det" :seed 7
                                            :source :fixture :timestamp 100))
         (b2 (compile-fixture-replay-bundle (list snap)
                                            :bundle-id "det" :seed 7
                                            :source :fixture :timestamp 100)))
    (is = (frb-event-count b1) (frb-event-count b2))
    (is = (frb-snapshot-count b1) (frb-snapshot-count b2))
    (is string= (rstr-stream-id (first (frb-streams b1)))
        (rstr-stream-id (first (frb-streams b2))))
    (is string= (ae-checksum (first (frb-artifacts b1)))
        (ae-checksum (first (frb-artifacts b2))))
    (is string= (first (frb-fixture-corpus b1))
        (first (frb-fixture-corpus b2)))))

(define-test (fixture-replay-compiler compile-live-source)
  (let* ((snap (make-frc-snapshot
                :events (list (make-frc-domain-event :message "live-ev" :timestamp 99))))
         (bundle (compile-fixture-replay-bundle (list snap)
                                                :bundle-id "live-b"
                                                :seed 0
                                                :source :live
                                                :timestamp 2000)))
    (is eq :live (frb-source bundle))
    (is eq :live (rstr-source (first (frb-streams bundle))))
    (is eq :live (ae-source (first (frb-artifacts bundle))))))

(define-test (fixture-replay-compiler compile-default-bundle-id)
  (let* ((snap (make-frc-snapshot
                :events (list (make-frc-domain-event :message "x" :timestamp 1))))
         (bundle (compile-fixture-replay-bundle (list snap))))
    (is string= "" (frb-bundle-id bundle))
    (is string= "bundle-s0" (rstr-stream-id (first (frb-streams bundle))))))

(define-test (fixture-replay-compiler artifact-valid-for-each-stream)
  (let* ((snap1 (make-frc-snapshot
                 :events (list (make-frc-domain-event :message "m1" :timestamp 10))))
         (snap2 (make-frc-snapshot
                 :events (list (make-frc-domain-event :message "m2" :timestamp 20)
                               (make-frc-domain-event :message "m3" :timestamp 30))))
         (bundle (compile-fixture-replay-bundle (list snap1 snap2)
                                                :bundle-id "val"
                                                :seed 0
                                                :source :fixture
                                                :timestamp 500)))
    (let ((a1 (first (frb-artifacts bundle)))
          (a2 (second (frb-artifacts bundle))))
      (true (ae-valid-p a1))
      (true (ae-valid-p a2))
      (is = 1 (ae-payload-size a1))
      (is = 2 (ae-payload-size a2))
      (is string= "art-val-s0" (ae-artifact-id a1))
      (is string= "art-val-s1" (ae-artifact-id a2)))))

(define-test (fixture-replay-compiler metadata-passthrough)
  (let* ((snap (make-frc-snapshot
                :events (list (make-frc-domain-event :message "m" :timestamp 1))
                :sync-token "my-sync-token-42"))
         (bundle (compile-fixture-replay-bundle (list snap)
                                                :bundle-id "meta"
                                                :seed 0
                                                :source :fixture
                                                :timestamp 100)))
    (is string= "my-sync-token-42"
        (rstr-metadata (first (frb-streams bundle))))))
