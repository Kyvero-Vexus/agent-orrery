;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; schema-gen-tests.lisp — Tests for property-based schema regression generators
;;;

(in-package #:orrery/harness-tests)

(define-test schema-gen)

;;; ─── gen-state / gen-next-raw ───

(define-test (schema-gen raw-advances-counter)
  (let* ((s0 (make-gen-state :seed 42))
         (_ (gen-next-raw s0)))
    (declare (ignore _))
    (multiple-value-bind (v s1) (gen-next-raw s0)
      (declare (ignore v))
      (is = 1 (gs-counter s1)))))

(define-test (schema-gen raw-deterministic)
  (let ((s1 (make-gen-state :seed 42))
        (s2 (make-gen-state :seed 42)))
    (multiple-value-bind (v1 _) (gen-next-raw s1)
      (declare (ignore _))
      (multiple-value-bind (v2 _2) (gen-next-raw s2)
        (declare (ignore _2))
        (is = v1 v2)))))

(define-test (schema-gen different-seeds-differ)
  (let ((s1 (make-gen-state :seed 1))
        (s2 (make-gen-state :seed 999)))
    (multiple-value-bind (v1 _) (gen-next-raw s1)
      (declare (ignore _))
      (multiple-value-bind (v2 _2) (gen-next-raw s2)
        (declare (ignore _2))
        (false (= v1 v2))))))

;;; ─── gen-integer ───

(define-test (schema-gen integer-in-range)
  (let ((s (make-gen-state :seed 77)))
    (dotimes (i 20)
      (multiple-value-bind (v ns) (gen-integer s 5 10)
        (true (and (>= v 5) (<= v 10)))
        (setf s ns)))))

;;; ─── gen-element ───

(define-test (schema-gen element-from-list)
  (let ((s (make-gen-state :seed 123))
        (choices '(:a :b :c)))
    (multiple-value-bind (v _) (gen-element s choices)
      (declare (ignore _))
      (true (member v choices)))))

;;; ─── gen-string ───

(define-test (schema-gen string-length)
  (let ((s (make-gen-state :seed 55)))
    (multiple-value-bind (str _) (gen-string s 8)
      (declare (ignore _))
      (is = 8 (length str)))))

(define-test (schema-gen string-deterministic)
  (let ((s1 (make-gen-state :seed 55))
        (s2 (make-gen-state :seed 55)))
    (multiple-value-bind (str1 _) (gen-string s1 8)
      (declare (ignore _))
      (multiple-value-bind (str2 _2) (gen-string s2 8)
        (declare (ignore _2))
        (is string= str1 str2)))))

;;; ─── gen-replay-event ───

(define-test (schema-gen event-valid-type)
  (let ((s (make-gen-state :seed 88)))
    (multiple-value-bind (ev _) (gen-replay-event s 1)
      (declare (ignore _))
      (true (member (re-event-type ev) '(:session :cron :health :usage :event :alert :probe)))
      (is = 1 (re-sequence-id ev))
      (true (> (length (re-payload ev)) 0)))))

;;; ─── gen-replay-stream ───

(define-test (schema-gen stream-event-count)
  (let ((s (make-gen-state :seed 42)))
    (multiple-value-bind (stream _) (gen-replay-stream s 5)
      (declare (ignore _))
      (is = 5 (length (rstr-events stream)))
      (is eq :synthetic (rstr-source stream)))))

(define-test (schema-gen stream-monotonic-ids)
  (let ((s (make-gen-state :seed 42)))
    (multiple-value-bind (stream _) (gen-replay-stream s 10)
      (declare (ignore _))
      (let ((ids (mapcar #'re-sequence-id (rstr-events stream))))
        (true (equal ids (sort (copy-list ids) #'<)))))))

;;; ─── gen-field-sig ───

(define-test (schema-gen field-valid-type)
  (let ((s (make-gen-state :seed 33)))
    (multiple-value-bind (f _) (gen-field-sig s)
      (declare (ignore _))
      (true (member (fs-field-type f) '(:string :integer :boolean :list :object :null :unknown)))
      (true (> (length (fs-name f)) 0)))))

;;; ─── gen-schema-sig ───

(define-test (schema-gen schema-field-count)
  (let ((s (make-gen-state :seed 44)))
    (multiple-value-bind (sig _) (gen-schema-sig s "events" 4)
      (declare (ignore _))
      (is = 4 (length (ss-fields sig)))
      (is string= "events" (ss-endpoint sig)))))

;;; ─── gen-schema-pair ───

(define-test (schema-gen pair-fixture-full)
  (let ((s (make-gen-state :seed 55)))
    (multiple-value-bind (fix live _) (gen-schema-pair s "sessions" 3)
      (declare (ignore _))
      (is = 3 (length (ss-fields fix)))
      ;; Live may have fewer fields (drift)
      (true (<= (length (ss-fields live)) (length (ss-fields fix)))))))

;;; ─── gen-snapshot-token ───

(define-test (schema-gen snapshot-token-prefix)
  (let ((s (make-gen-state :seed 66)))
    (multiple-value-bind (tok _) (gen-snapshot-token s)
      (declare (ignore _))
      (true (search "snap-" tok)))))

;;; ─── gen-snapshot-sequence ───

(define-test (schema-gen snapshot-sequence-count)
  (let ((s (make-gen-state :seed 77)))
    (multiple-value-bind (tokens _) (gen-snapshot-sequence s 5)
      (declare (ignore _))
      (is = 5 (length tokens)))))

;;; ─── gen-regression-corpus ───

(define-test (schema-gen corpus-structure)
  (let ((corpus (gen-regression-corpus 42)))
    (is = 3 (length (rc-streams corpus)))
    (is = 2 (length (rc-fixture-sigs corpus)))
    (is = 2 (length (rc-live-sigs corpus)))
    (is = 3 (length (rc-snapshots corpus)))
    (is = 42 (rc-seed corpus))))

(define-test (schema-gen corpus-deterministic)
  (let ((c1 (gen-regression-corpus 42))
        (c2 (gen-regression-corpus 42)))
    (is string= (rc-corpus-id c1) (rc-corpus-id c2))
    (is = (length (rc-streams c1)) (length (rc-streams c2)))
    ;; Check first stream has same events
    (let ((s1 (first (rc-streams c1)))
          (s2 (first (rc-streams c2))))
      (is string= (rstr-stream-id s1) (rstr-stream-id s2))
      (is = (length (rstr-events s1)) (length (rstr-events s2))))))

(define-test (schema-gen corpus-different-seeds)
  (let ((c1 (gen-regression-corpus 1))
        (c2 (gen-regression-corpus 999)))
    (false (string= (rc-corpus-id c1) (rc-corpus-id c2)))))

(define-test (schema-gen corpus-custom-params)
  (let ((corpus (gen-regression-corpus 42
                  :stream-count 5
                  :events-per-stream 10
                  :endpoint-count 3
                  :fields-per-schema 6)))
    (is = 5 (length (rc-streams corpus)))
    (is = 10 (length (rstr-events (first (rc-streams corpus)))))
    (is = 3 (length (rc-fixture-sigs corpus)))))

;;; ─── Integration: corpus through decision pipeline ───

(define-test (schema-gen corpus-feeds-pipeline)
  (let* ((corpus (gen-regression-corpus 42))
         (stream (first (rc-streams corpus)))
         (decision (replay-to-decision stream)))
    ;; Should produce a valid decision
    (true (member (dec-verdict decision) '(:pass :degraded :fail)))
    (true (>= (dec-finding-count decision) 1))))

(define-test (schema-gen corpus-feeds-schema-compat)
  (let* ((corpus (gen-regression-corpus 42))
         (fix (first (rc-fixture-sigs corpus)))
         (live (first (rc-live-sigs corpus)))
         (report (check-schema-compatibility fix live)))
    (true (compat-report-p report))))
