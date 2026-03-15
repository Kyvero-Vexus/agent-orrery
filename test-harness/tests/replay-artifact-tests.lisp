;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; replay-artifact-tests.lisp — Tests for replay artifact schema + validators
;;;

(in-package #:orrery/harness-tests)

(define-test replay-artifact)

;;; ─── Helpers ───

(defun make-valid-envelope (&key (id "art-1") (kind :replay-stream))
  (make-artifact-envelope
   :artifact-id id :kind kind :version "1.0.0"
   :created-at 1000 :source :fixture :checksum "abc123"
   :payload-size 100))

(defun make-valid-stream ()
  (make-replay-stream
   :stream-id "s1" :source :fixture
   :events (list (make-replay-event :sequence-id 1 :event-type :session :payload "data")
                 (make-replay-event :sequence-id 2 :event-type :health :payload "ok"))
   :seed 42))

;;; ─── validate-required-string ───

(define-test (replay-artifact required-string-valid)
  (is eq nil (validate-required-string "f" "hello")))

(define-test (replay-artifact required-string-empty)
  (let ((e (validate-required-string "f" "")))
    (true (validation-error-p e))
    (is eq :missing (ve-code e))
    (is eq :fatal (ve-severity e))))

;;; ─── validate-integer-range ───

(define-test (replay-artifact range-valid)
  (is eq nil (validate-integer-range "n" 50 0 100)))

(define-test (replay-artifact range-below)
  (let ((e (validate-integer-range "n" -1 0 100)))
    (true (validation-error-p e))
    (is eq :range (ve-code e))))

(define-test (replay-artifact range-above)
  (let ((e (validate-integer-range "n" 101 0 100)))
    (true (validation-error-p e))))

(define-test (replay-artifact range-boundary)
  (is eq nil (validate-integer-range "n" 0 0 100))
  (is eq nil (validate-integer-range "n" 100 0 100)))

;;; ─── validate-version-format ───

(define-test (replay-artifact version-valid)
  (is eq nil (validate-version-format "v" "1.0.0")))

(define-test (replay-artifact version-invalid)
  (let ((e (validate-version-format "v" "bad")))
    (true (validation-error-p e))
    (is eq :version-mismatch (ve-code e))
    (is eq :warning (ve-severity e))))

;;; ─── validate-envelope ───

(define-test (replay-artifact envelope-valid)
  (let ((env (make-valid-envelope)))
    (is = 0 (length (validate-envelope env)))))

(define-test (replay-artifact envelope-missing-id)
  (let* ((env (make-artifact-envelope
               :artifact-id "" :kind :replay-stream :version "1.0.0"
               :checksum "abc" :created-at 100))
         (errors (validate-envelope env)))
    (true (find :missing errors :key #'ve-code))))

(define-test (replay-artifact envelope-missing-checksum)
  (let* ((env (make-artifact-envelope
               :artifact-id "a1" :kind :replay-stream :version "1.0.0"
               :checksum "" :created-at 100))
         (errors (validate-envelope env)))
    (true (find :missing errors :key #'ve-code))))

;;; ─── validate-stream-artifact ───

(define-test (replay-artifact stream-valid)
  (let ((s (make-valid-stream)))
    (is = 0 (length (validate-stream-artifact s)))))

(define-test (replay-artifact stream-empty-events)
  (let* ((s (make-replay-stream :stream-id "s1" :events '()))
         (errors (validate-stream-artifact s)))
    (true (find :empty-payload errors :key #'ve-code))))

(define-test (replay-artifact stream-bad-ordering)
  (let* ((s (make-replay-stream
             :stream-id "s1"
             :events (list (make-replay-event :sequence-id 5 :event-type :session :payload "a")
                           (make-replay-event :sequence-id 2 :event-type :health :payload "b"))))
         (errors (validate-stream-artifact s)))
    (true (find :ordering errors :key #'ve-code))
    (is eq :fatal (ve-severity (find :ordering errors :key #'ve-code)))))

(define-test (replay-artifact stream-empty-payload-warning)
  (let* ((s (make-replay-stream
             :stream-id "s1"
             :events (list (make-replay-event :sequence-id 1 :event-type :session :payload ""))))
         (errors (validate-stream-artifact s)))
    (true (find :missing errors :key #'ve-code))
    (is eq :warning (ve-severity (find :missing errors :key #'ve-code)))))

(define-test (replay-artifact stream-missing-id)
  (let* ((s (make-replay-stream :stream-id "" :events (list (make-replay-event :sequence-id 1 :event-type :session :payload "x"))))
         (errors (validate-stream-artifact s)))
    (true (find :missing errors :key #'ve-code))))

;;; ─── validate-decision-artifact ───

(define-test (replay-artifact decision-valid)
  (let* ((findings (list (make-probe-finding :severity 10 :domain :transport)))
         (dec (run-decision-pipeline findings)))
    (is = 0 (length (validate-decision-artifact dec)))))

(define-test (replay-artifact decision-count-mismatch)
  ;; Create a record with wrong finding-count
  (let ((dec (make-decision-record
              :verdict :pass :aggregate-score 10 :max-severity 10
              :finding-count 5 :findings '()
              :reasoning "test")))
    (let ((errors (validate-decision-artifact dec)))
      (true (find :reference errors :key #'ve-code)))))

;;; ─── validate-corpus-artifact ───

(define-test (replay-artifact corpus-valid)
  (let ((corpus (gen-regression-corpus 42)))
    (is = 0 (length (validate-corpus-artifact corpus)))))

(define-test (replay-artifact corpus-empty-streams)
  (let ((corpus (make-regression-corpus :corpus-id "c1" :seed 1 :streams '()
                                         :fixture-sigs '() :live-sigs '())))
    (let ((errors (validate-corpus-artifact corpus)))
      (true (find :empty-payload errors :key #'ve-code)))))

(define-test (replay-artifact corpus-mismatched-sigs)
  (let* ((f (make-schema-sig :endpoint "e1" :version "1" :fields '()))
         (corpus (make-regression-corpus
                  :corpus-id "c1" :seed 1
                  :streams (list (make-valid-stream))
                  :fixture-sigs (list f)
                  :live-sigs '())))
    (let ((errors (validate-corpus-artifact corpus)))
      (true (find :reference errors :key #'ve-code)))))

;;; ─── summarize-validation ───

(define-test (replay-artifact summarize-no-errors)
  (multiple-value-bind (valid-p errors) (summarize-validation '())
    (true valid-p)
    (is = 0 (length errors))))

(define-test (replay-artifact summarize-with-fatal)
  (let ((errs (list (make-validation-error :severity :fatal :code :missing))))
    (multiple-value-bind (valid-p _) (summarize-validation errs)
      (declare (ignore _))
      (false valid-p))))

(define-test (replay-artifact summarize-warnings-pass)
  (let ((errs (list (make-validation-error :severity :warning :code :version-mismatch))))
    (multiple-value-bind (valid-p _) (summarize-validation errs)
      (declare (ignore _))
      (true valid-p))))

;;; ─── run-artifact-validation ───

(define-test (replay-artifact full-validation-pass)
  (let* ((stream (make-valid-stream))
         (env (make-valid-envelope))
         (result (run-artifact-validation env stream)))
    (true (ae-valid-p result))
    (is = 0 (length (ae-errors result)))))

(define-test (replay-artifact full-validation-envelope-fail)
  (let* ((stream (make-valid-stream))
         (env (make-artifact-envelope
               :artifact-id "" :kind :replay-stream :version "1.0.0"
               :checksum "abc" :created-at 100))
         (result (run-artifact-validation env stream)))
    (false (ae-valid-p result))))

(define-test (replay-artifact full-validation-payload-fail)
  (let* ((bad-stream (make-replay-stream
                      :stream-id "s1"
                      :events (list (make-replay-event :sequence-id 5 :event-type :session :payload "a")
                                    (make-replay-event :sequence-id 2 :event-type :health :payload "b"))))
         (env (make-valid-envelope))
         (result (run-artifact-validation env bad-stream)))
    (false (ae-valid-p result))))

(define-test (replay-artifact full-validation-decision-payload)
  (let* ((findings (list (make-probe-finding :severity 10 :domain :transport)))
         (dec (run-decision-pipeline findings))
         (env (make-valid-envelope :kind :decision-snapshot))
         (result (run-artifact-validation env dec)))
    (true (ae-valid-p result))))

(define-test (replay-artifact full-validation-corpus-payload)
  (let* ((corpus (gen-regression-corpus 42))
         (env (make-valid-envelope :kind :schema-corpus))
         (result (run-artifact-validation env corpus)))
    (true (ae-valid-p result))))
