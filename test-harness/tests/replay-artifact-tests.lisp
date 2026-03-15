;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; replay-artifact-tests.lisp — Tests for typed replay artifact schema + validators
;;;

(in-package #:orrery/harness-tests)

(define-test replay-artifact)

;;; ─── Artifact Taxonomy Types ───

(define-test (replay-artifact kind-types)
  :description "artifact-kind includes all expected members"
  (dolist (k '(:replay-stream :decision-snapshot :schema-corpus
               :invariant-report :evidence-bundle))
    (true (typep k 'artifact-kind))))

(define-test (replay-artifact validation-code-types)
  :description "validation-code includes all expected members"
  (dolist (c '(:missing :type-mismatch :range :reference :checksum
               :version-mismatch :ordering :empty-payload))
    (true (typep c 'validation-code))))

(define-test (replay-artifact error-severity-types)
  :description "error-severity includes all expected members"
  (dolist (s '(:fatal :error :warning))
    (true (typep s 'error-severity))))

;;; ─── Validation Error Construction ───

(define-test (replay-artifact make-validation-error-fields)
  :description "validation-error stores all fields correctly"
  (let ((ve (make-validation-error
             :field "test-field"
             :code :missing
             :message "Test message"
             :severity :fatal)))
    (is string= "test-field" (ve-field ve))
    (is eq :missing (ve-code ve))
    (is string= "Test message" (ve-message ve))
    (is eq :fatal (ve-severity ve))))

;;; ─── Artifact Envelope Construction ───

(define-test (replay-artifact make-envelope-defaults)
  :description "artifact-envelope defaults are well-typed"
  (let ((env (make-artifact-envelope
              :artifact-id "art-001"
              :kind :replay-stream
              :source :fixture
              :checksum "abc123")))
    (is string= "art-001" (ae-artifact-id env))
    (is eq :replay-stream (ae-kind env))
    (is string= "1.0.0" (ae-version env))
    (is = 0 (ae-created-at env))
    (is eq :fixture (ae-source env))
    (is string= "abc123" (ae-checksum env))
    (is = 0 (ae-payload-size env))
    (false (ae-valid-p env))
    (is = 0 (length (ae-errors env)))))

;;; ─── Field Validators ───

(define-test (replay-artifact validate-required-string-ok)
  :description "validate-required-string returns nil for non-empty"
  (is eq nil (validate-required-string "f" "hello")))

(define-test (replay-artifact validate-required-string-empty)
  :description "validate-required-string rejects empty string"
  (let ((ve (validate-required-string "f" "")))
    (true (validation-error-p ve))
    (is eq :missing (ve-code ve))
    (is eq :fatal (ve-severity ve))))

(define-test (replay-artifact validate-integer-range-ok)
  :description "validate-integer-range accepts in-range value"
  (is eq nil (validate-integer-range "n" 5 0 10)))

(define-test (replay-artifact validate-integer-range-low)
  :description "validate-integer-range rejects below-min"
  (let ((ve (validate-integer-range "n" -1 0 10)))
    (true (validation-error-p ve))
    (is eq :range (ve-code ve))))

(define-test (replay-artifact validate-integer-range-high)
  :description "validate-integer-range rejects above-max"
  (let ((ve (validate-integer-range "n" 11 0 10)))
    (true (validation-error-p ve))))

(define-test (replay-artifact validate-version-format-ok)
  :description "validate-version-format accepts X.Y.Z"
  (is eq nil (validate-version-format "v" "1.0.0")))

(define-test (replay-artifact validate-version-format-bad)
  :description "validate-version-format rejects bad version"
  (let ((ve (validate-version-format "v" "abc")))
    (true (validation-error-p ve))
    (is eq :version-mismatch (ve-code ve))))

;;; ─── Envelope Validation ───

(define-test (replay-artifact validate-envelope-valid)
  :description "validate-envelope returns empty list for valid envelope"
  (let* ((env (make-artifact-envelope
               :artifact-id "art-001"
               :kind :replay-stream
               :version "1.0.0"
               :created-at 1000
               :source :fixture
               :checksum "sha256:abc"
               :payload-size 100))
         (errors (validate-envelope env)))
    (is = 0 (length errors))))

(define-test (replay-artifact validate-envelope-missing-id)
  :description "validate-envelope catches empty artifact-id"
  (let* ((env (make-artifact-envelope
               :artifact-id ""
               :kind :replay-stream
               :source :fixture
               :checksum "sha256:abc"))
         (errors (validate-envelope env)))
    (true (> (length errors) 0))
    (true (some (lambda (e) (string= "artifact-id" (ve-field e))) errors))))

(define-test (replay-artifact validate-envelope-missing-checksum)
  :description "validate-envelope catches empty checksum"
  (let* ((env (make-artifact-envelope
               :artifact-id "art-001"
               :kind :replay-stream
               :source :fixture
               :checksum ""))
         (errors (validate-envelope env)))
    (true (some (lambda (e) (string= "checksum" (ve-field e))) errors))))

;;; ─── Stream Artifact Validation ───

(define-test (replay-artifact validate-stream-valid)
  :description "validate-stream-artifact passes for well-formed stream"
  (let* ((ev1 (make-replay-event :sequence-id 1 :event-type :session
                                 :payload "{}" :timestamp 100))
         (ev2 (make-replay-event :sequence-id 2 :event-type :health
                                 :payload "{}" :timestamp 200))
         (stream (make-replay-stream :stream-id "s-001"
                                     :source :fixture
                                     :events (list ev1 ev2)))
         (errors (validate-stream-artifact stream)))
    (is = 0 (length errors))))

(define-test (replay-artifact validate-stream-empty-events)
  :description "validate-stream-artifact catches empty event list"
  (let* ((stream (make-replay-stream :stream-id "s-001"
                                     :source :fixture
                                     :events '()))
         (errors (validate-stream-artifact stream)))
    (true (some (lambda (e) (eq :empty-payload (ve-code e))) errors))))

(define-test (replay-artifact validate-stream-bad-ordering)
  :description "validate-stream-artifact catches non-monotonic sequence-ids"
  (let* ((ev1 (make-replay-event :sequence-id 5 :event-type :session
                                 :payload "{}" :timestamp 100))
         (ev2 (make-replay-event :sequence-id 3 :event-type :health
                                 :payload "{}" :timestamp 200))
         (stream (make-replay-stream :stream-id "s-001"
                                     :source :fixture
                                     :events (list ev1 ev2)))
         (errors (validate-stream-artifact stream)))
    (true (some (lambda (e) (eq :ordering (ve-code e))) errors))))

(define-test (replay-artifact validate-stream-empty-payload)
  :description "validate-stream-artifact warns on empty event payload"
  (let* ((ev1 (make-replay-event :sequence-id 1 :event-type :session
                                 :payload "" :timestamp 100))
         (stream (make-replay-stream :stream-id "s-001"
                                     :source :fixture
                                     :events (list ev1)))
         (errors (validate-stream-artifact stream)))
    (true (some (lambda (e) (eq :missing (ve-code e))) errors))))

;;; ─── Decision Artifact Validation ───

(define-test (replay-artifact validate-decision-valid)
  :description "validate-decision-artifact passes for well-formed record"
  (let* ((rec (make-decision-record
               :verdict :pass
               :aggregate-score 15
               :max-severity 10
               :finding-count 0
               :findings '()
               :reasoning "All clear"))
         (errors (validate-decision-artifact rec)))
    (is = 0 (length errors))))

(define-test (replay-artifact validate-decision-bad-count)
  :description "validate-decision-artifact catches count mismatch"
  (let* ((f1 (make-probe-finding :domain :runtime :status :healthy
                                 :severity 5 :message "ok"))
         (rec (make-decision-record
               :verdict :pass
               :aggregate-score 15
               :max-severity 10
               :finding-count 5
               :findings (list f1)
               :reasoning "Mismatch"))
         (errors (validate-decision-artifact rec)))
    (true (some (lambda (e) (eq :reference (ve-code e))) errors))))

(define-test (replay-artifact validate-decision-empty-reasoning)
  :description "validate-decision-artifact catches empty reasoning"
  (let* ((rec (make-decision-record
               :verdict :pass
               :aggregate-score 15
               :max-severity 10
               :finding-count 0
               :findings '()
               :reasoning ""))
         (errors (validate-decision-artifact rec)))
    (true (some (lambda (e) (string= "reasoning" (ve-field e))) errors))))

;;; ─── Corpus Validation ───

(define-test (replay-artifact validate-corpus-valid)
  :description "validate-corpus-artifact passes for well-formed corpus"
  (let* ((ev1 (make-replay-event :sequence-id 1 :event-type :session
                                 :payload "{}" :timestamp 100))
         (stream (make-replay-stream :stream-id "s-001"
                                     :source :fixture
                                     :events (list ev1)))
         (corpus (make-regression-corpus
                  :corpus-id "c-001"
                  :seed 42
                  :streams (list stream)
                  :fixture-sigs '("sig-a")
                  :live-sigs '("sig-b")))
         (errors (validate-corpus-artifact corpus)))
    (is = 0 (length errors))))

(define-test (replay-artifact validate-corpus-empty-streams)
  :description "validate-corpus-artifact catches empty stream list"
  (let* ((corpus (make-regression-corpus
                  :corpus-id "c-001"
                  :seed 42
                  :streams '()
                  :fixture-sigs '("a")
                  :live-sigs '("b")))
         (errors (validate-corpus-artifact corpus)))
    (true (some (lambda (e) (eq :empty-payload (ve-code e))) errors))))

(define-test (replay-artifact validate-corpus-sig-mismatch)
  :description "validate-corpus-artifact catches fixture/live sig count mismatch"
  (let* ((ev1 (make-replay-event :sequence-id 1 :event-type :session
                                 :payload "{}" :timestamp 100))
         (stream (make-replay-stream :stream-id "s-001"
                                     :source :fixture
                                     :events (list ev1)))
         (corpus (make-regression-corpus
                  :corpus-id "c-001"
                  :seed 42
                  :streams (list stream)
                  :fixture-sigs '("a" "b")
                  :live-sigs '("c")))
         (errors (validate-corpus-artifact corpus)))
    (true (some (lambda (e) (eq :reference (ve-code e))) errors))))

;;; ─── Summarize Validation ───

(define-test (replay-artifact summarize-no-errors)
  :description "summarize-validation returns valid for empty list"
  (multiple-value-bind (valid-p errors) (summarize-validation '())
    (true valid-p)
    (is = 0 (length errors))))

(define-test (replay-artifact summarize-with-fatal)
  :description "summarize-validation returns invalid when fatal present"
  (let ((errs (list (make-validation-error
                     :field "x" :code :missing :message "m" :severity :fatal))))
    (multiple-value-bind (valid-p errors) (summarize-validation errs)
      (false valid-p)
      (is = 1 (length errors)))))

(define-test (replay-artifact summarize-warnings-only)
  :description "summarize-validation returns valid when only warnings"
  (let ((errs (list (make-validation-error
                     :field "x" :code :range :message "m" :severity :warning))))
    (multiple-value-bind (valid-p _) (summarize-validation errs)
      (declare (ignore _))
      (true valid-p))))

;;; ─── Full Pipeline ───

(define-test (replay-artifact run-pipeline-valid)
  :description "run-artifact-validation returns valid envelope for good data"
  (let* ((ev1 (make-replay-event :sequence-id 1 :event-type :session
                                 :payload "{\"status\":\"ok\"}" :timestamp 100))
         (ev2 (make-replay-event :sequence-id 2 :event-type :health
                                 :payload "{\"component\":\"api\"}" :timestamp 200))
         (stream (make-replay-stream :stream-id "s-001"
                                     :source :fixture
                                     :events (list ev1 ev2)))
         (env (make-artifact-envelope
               :artifact-id "art-001"
               :kind :replay-stream
               :version "1.0.0"
               :created-at 1000
               :source :fixture
               :checksum "sha256:abc123"
               :payload-size 256))
         (result (run-artifact-validation env stream)))
    (true (ae-valid-p result))
    (is = 0 (length (ae-errors result)))))

(define-test (replay-artifact run-pipeline-invalid-envelope)
  :description "run-artifact-validation catches envelope errors"
  (let* ((ev1 (make-replay-event :sequence-id 1 :event-type :session
                                 :payload "{}" :timestamp 100))
         (stream (make-replay-stream :stream-id "s-001"
                                     :source :fixture
                                     :events (list ev1)))
         (env (make-artifact-envelope
               :artifact-id ""
               :kind :replay-stream
               :source :fixture
               :checksum ""))
         (result (run-artifact-validation env stream)))
    (false (ae-valid-p result))
    (true (> (length (ae-errors result)) 0))))

(define-test (replay-artifact run-pipeline-decision-payload)
  :description "run-artifact-validation validates decision payload"
  (let* ((rec (make-decision-record
               :verdict :pass
               :aggregate-score 15
               :max-severity 10
               :finding-count 0
               :findings '()
               :reasoning "All probes healthy"))
         (env (make-artifact-envelope
               :artifact-id "art-002"
               :kind :decision-snapshot
               :version "1.0.0"
               :created-at 2000
               :source :live
               :checksum "sha256:def456"
               :payload-size 128))
         (result (run-artifact-validation env rec)))
    (true (ae-valid-p result))
    (is = 0 (length (ae-errors result)))))
