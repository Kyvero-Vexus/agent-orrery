;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-invariant-tests.lisp — Tests for gate-invariant checker
;;;

(in-package #:orrery/harness-tests)

(define-test gate-invariant)

;;; ─── Helpers ───

(defun make-inv-event (seq payload &optional (etype :session))
  (make-replay-event :sequence-id seq :event-type etype :payload payload))

(defun make-inv-stream (events &key (id "inv-test") (seed 42))
  (make-replay-stream :stream-id id :source :fixture :events events :seed seed))

(defun make-inv-field (name ftype &optional (required t))
  (make-field-sig :name name :field-type ftype :required-p required :path name))

;;; ─── check-ordering-invariant ───

(define-test (gate-invariant ordering-empty)
  (is = 0 (length (check-ordering-invariant '()))))

(define-test (gate-invariant ordering-single)
  (let ((events (list (make-inv-event 1 "a"))))
    (is = 0 (length (check-ordering-invariant events)))))

(define-test (gate-invariant ordering-valid)
  (let ((events (list (make-inv-event 1 "a") (make-inv-event 2 "b") (make-inv-event 3 "c"))))
    (is = 0 (length (check-ordering-invariant events)))))

(define-test (gate-invariant ordering-violation)
  (let* ((events (list (make-inv-event 3 "a") (make-inv-event 2 "b")))
         (violations (check-ordering-invariant events)))
    (is = 1 (length violations))
    (is eq :ordering (iv-category (first violations)))
    (is eq :critical (iv-severity (first violations)))))

(define-test (gate-invariant ordering-duplicate-ids)
  (let* ((events (list (make-inv-event 1 "a") (make-inv-event 1 "b")))
         (violations (check-ordering-invariant events)))
    (is = 1 (length violations))))

;;; ─── check-determinism-invariant ───

(define-test (gate-invariant determinism-holds)
  (let* ((events (list (make-inv-event 1 "data") (make-inv-event 2 "more")))
         (stream (make-inv-stream events))
         (th (make-severity-thresholds)))
    (is = 0 (length (check-determinism-invariant stream th)))))

(define-test (gate-invariant determinism-different-seeds-same-result)
  ;; Same content, same seed → deterministic regardless
  (let* ((events (list (make-inv-event 1 "x")))
         (stream (make-inv-stream events :seed 999))
         (th (make-severity-thresholds)))
    (is = 0 (length (check-determinism-invariant stream th)))))

;;; ─── check-schema-coverage-invariant ───

(define-test (gate-invariant schema-coverage-pass)
  (let* ((f (make-inv-field "id" :string))
         (fix (make-schema-sig :endpoint "sessions" :version "1" :fields (list f)))
         (live (make-schema-sig :endpoint "sessions" :version "1" :fields (list f)))
         (report (check-schema-compatibility fix live)))
    (is = 0 (length (check-schema-coverage-invariant report)))))

(define-test (gate-invariant schema-coverage-missing-required)
  (let* ((f (make-inv-field "id" :string t))
         (fix (make-schema-sig :endpoint "sessions" :version "1" :fields (list f)))
         (live (make-schema-sig :endpoint "sessions" :version "1" :fields '()))
         (report (check-schema-compatibility fix live)))
    (let ((violations (check-schema-coverage-invariant report)))
      (is = 1 (length violations))
      (is eq :schema-coverage (iv-category (first violations)))
      (is eq :critical (iv-severity (first violations))))))

(define-test (gate-invariant schema-coverage-missing-optional-no-critical)
  (let* ((f (make-inv-field "tag" :string nil))
         (fix (make-schema-sig :endpoint "events" :version "1" :fields (list f)))
         (live (make-schema-sig :endpoint "events" :version "1" :fields '()))
         (report (check-schema-compatibility fix live)))
    ;; Optional field missing is degrading, not breaking — no critical violations
    (is = 0 (length (check-schema-coverage-invariant report)))))

;;; ─── check-decision-consistency-invariant ───

(define-test (gate-invariant consistency-pass-correct)
  (let* ((findings (list (make-probe-finding :severity 10 :domain :transport)))
         (dec (run-decision-pipeline findings))
         (th (make-severity-thresholds)))
    (is = 0 (length (check-decision-consistency-invariant dec th)))))

(define-test (gate-invariant consistency-fail-correct)
  (let* ((findings (list (make-probe-finding :severity 90 :domain :auth)))
         (dec (run-decision-pipeline findings))
         (th (make-severity-thresholds)))
    ;; severity 90 > 80 → :fail, consistent
    (is = 0 (length (check-decision-consistency-invariant dec th)))))

(define-test (gate-invariant consistency-degraded-correct)
  (let* ((findings (list (make-probe-finding :severity 40 :domain :transport)))
         (dec (run-decision-pipeline findings))
         (th (make-severity-thresholds)))
    (is = 0 (length (check-decision-consistency-invariant dec th)))))

;;; ─── build-invariant-report ───

(define-test (gate-invariant report-empty-pass)
  (let ((report (build-invariant-report '())))
    (true (ir-pass-p report))
    (is = 0 (ir-fail-count report))
    (is = 0 (ir-checked-count report))))

(define-test (gate-invariant report-critical-fails)
  (let* ((v (make-invariant-violation :category :ordering :severity :critical
                                       :description "bad" :evidence "x"))
         (report (build-invariant-report (list v))))
    (false (ir-pass-p report))
    (is = 1 (ir-fail-count report))))

(define-test (gate-invariant report-warning-passes)
  (let* ((v (make-invariant-violation :category :ordering :severity :warning
                                       :description "meh" :evidence "x"))
         (report (build-invariant-report (list v))))
    (true (ir-pass-p report))
    (is = 0 (ir-fail-count report))
    (is = 1 (ir-pass-count report))))

;;; ─── run-invariant-suite ───

(define-test (gate-invariant suite-all-pass)
  (let* ((events (list (make-inv-event 1 "data") (make-inv-event 2 "more")))
         (stream (make-inv-stream events))
         (decision (replay-to-decision stream))
         (f (make-inv-field "id" :string))
         (fix (make-schema-sig :endpoint "s" :version "1" :fields (list f)))
         (live (make-schema-sig :endpoint "s" :version "1" :fields (list f)))
         (compat (check-schema-compatibility fix live))
         (report (run-invariant-suite stream decision compat :timestamp 999)))
    (true (ir-pass-p report))
    (is = 999 (ir-timestamp report))
    (is = 0 (ir-fail-count report))))

(define-test (gate-invariant suite-ordering-failure)
  (let* ((events (list (make-inv-event 5 "a") (make-inv-event 2 "b")))
         (stream (make-inv-stream events))
         (decision (replay-to-decision stream))
         (f (make-inv-field "id" :string))
         (fix (make-schema-sig :endpoint "s" :version "1" :fields (list f)))
         (live (make-schema-sig :endpoint "s" :version "1" :fields (list f)))
         (compat (check-schema-compatibility fix live))
         (report (run-invariant-suite stream decision compat)))
    (false (ir-pass-p report))
    (true (find :ordering (ir-violations report) :key #'iv-category))))

(define-test (gate-invariant suite-schema-failure)
  (let* ((events (list (make-inv-event 1 "data")))
         (stream (make-inv-stream events))
         (decision (replay-to-decision stream))
         (f (make-inv-field "id" :string t))
         (fix (make-schema-sig :endpoint "s" :version "1" :fields (list f)))
         (live (make-schema-sig :endpoint "s" :version "1" :fields '()))
         (compat (check-schema-compatibility fix live))
         (report (run-invariant-suite stream decision compat)))
    (false (ir-pass-p report))
    (true (find :schema-coverage (ir-violations report) :key #'iv-category))))
