;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; replay-artifact.lisp — Typed replay artifact schema + validators
;;;
;;; Defines canonical schema for fixture/live replay artifacts consumed
;;; by Epic 2 gate, with composable validation pipeline.

(in-package #:orrery/adapter)

;;; ─── Artifact Taxonomy ───

(deftype artifact-kind ()
  "Categories of replay artifacts."
  '(member :replay-stream :decision-snapshot :schema-corpus
           :invariant-report :evidence-bundle))

(deftype validation-code ()
  "Machine-readable validation error codes."
  '(member :missing :type-mismatch :range :reference :checksum
           :version-mismatch :ordering :empty-payload))

(deftype error-severity ()
  "Validation error severity levels."
  '(member :fatal :error :warning))

;;; ─── Validation Error ───

(defstruct (validation-error
             (:constructor make-validation-error
                 (&key field code message severity))
             (:conc-name ve-))
  "One validation error in an artifact."
  (field "" :type string)
  (code :missing :type validation-code)
  (message "" :type string)
  (severity :error :type error-severity))

;;; ─── Artifact Envelope ───

(defstruct (artifact-envelope
             (:constructor make-artifact-envelope
                 (&key artifact-id kind version created-at source
                       checksum payload-size valid-p errors))
             (:conc-name ae-))
  "Envelope wrapping any replay artifact with metadata."
  (artifact-id "" :type string)
  (kind :replay-stream :type artifact-kind)
  (version "1.0.0" :type string)
  (created-at 0 :type (integer 0))
  (source :fixture :type replay-source)
  (checksum "" :type string)
  (payload-size 0 :type (integer 0))
  (valid-p nil :type boolean)
  (errors '() :type list))

;;; ─── Field Validators ───

(declaim (ftype (function (string string) (or null validation-error))
                validate-required-string))
(defun validate-required-string (field-name value)
  "Validate a required non-empty string field."
  (declare (optimize (safety 3)))
  (if (and (stringp value) (> (length value) 0))
      nil
      (make-validation-error
       :field field-name
       :code :missing
       :message (format nil "Required field ~A is empty or missing" field-name)
       :severity :fatal)))

(declaim (ftype (function (string integer integer integer) (or null validation-error))
                validate-integer-range))
(defun validate-integer-range (field-name value min max)
  "Validate an integer is within [min, max]."
  (declare (optimize (safety 3)))
  (if (and (integerp value) (>= value min) (<= value max))
      nil
      (make-validation-error
       :field field-name
       :code :range
       :message (format nil "Field ~A value ~A not in range [~D, ~D]"
                        field-name value min max)
       :severity :error)))

(declaim (ftype (function (string string) (or null validation-error))
                validate-version-format))
(defun validate-version-format (field-name version)
  "Validate version string matches X.Y.Z pattern."
  (declare (optimize (safety 3)))
  (if (and (stringp version)
           (>= (length version) 5)
           (digit-char-p (char version 0))
           (find #\. version))
      nil
      (make-validation-error
       :field field-name
       :code :version-mismatch
       :message (format nil "Version ~A does not match expected format" version)
       :severity :warning)))

;;; ─── Envelope Validator ───

(declaim (ftype (function (artifact-envelope) list) validate-envelope))
(defun validate-envelope (envelope)
  "Validate artifact envelope fields. Returns list of validation-errors."
  (declare (optimize (safety 3)))
  (let ((errors '()))
    ;; Required: artifact-id
    (let ((e (validate-required-string "artifact-id" (ae-artifact-id envelope))))
      (when e (push e errors)))
    ;; Required: checksum
    (let ((e (validate-required-string "checksum" (ae-checksum envelope))))
      (when e (push e errors)))
    ;; Version format
    (let ((e (validate-version-format "version" (ae-version envelope))))
      (when e (push e errors)))
    ;; Created-at range (not in far future)
    (let ((e (validate-integer-range "created-at" (ae-created-at envelope)
                                     0 (expt 2 40))))
      (when e (push e errors)))
    ;; Payload size positive
    (when (< (ae-payload-size envelope) 0)
      (push (make-validation-error
             :field "payload-size"
             :code :range
             :message "Payload size cannot be negative"
             :severity :error)
            errors))
    (nreverse errors)))

;;; ─── Stream Artifact Validator ───

(declaim (ftype (function (replay-stream) list) validate-stream-artifact))
(defun validate-stream-artifact (stream)
  "Validate a replay-stream as a well-formed artifact."
  (declare (optimize (safety 3)))
  (let ((errors '()))
    ;; Stream-id required
    (let ((e (validate-required-string "stream-id" (rstr-stream-id stream))))
      (when e (push e errors)))
    ;; Must have events
    (when (null (rstr-events stream))
      (push (make-validation-error
             :field "events"
             :code :empty-payload
             :message "Replay stream has no events"
             :severity :error)
            errors))
    ;; Event ordering (monotonic sequence-ids)
    (when (rstr-events stream)
      (let ((ordering-violations (check-ordering-invariant (rstr-events stream))))
        (dolist (v ordering-violations)
          (push (make-validation-error
                 :field "events.sequence-id"
                 :code :ordering
                 :message (iv-description v)
                 :severity :fatal)
                errors))))
    ;; Each event has non-empty payload
    (dolist (ev (rstr-events stream))
      (when (string= (re-payload ev) "")
        (push (make-validation-error
               :field (format nil "events[~D].payload" (re-sequence-id ev))
               :code :missing
               :message (format nil "Event ~D has empty payload" (re-sequence-id ev))
               :severity :warning)
              errors)))
    (nreverse errors)))

;;; ─── Decision Snapshot Validator ───

(declaim (ftype (function (decision-record) list) validate-decision-artifact))
(defun validate-decision-artifact (record)
  "Validate a decision-record as a well-formed artifact."
  (declare (optimize (safety 3)))
  (let ((errors '()))
    ;; Score ranges
    (let ((e (validate-integer-range "aggregate-score"
                                     (dec-aggregate-score record) 0 100)))
      (when e (push e errors)))
    (let ((e (validate-integer-range "max-severity"
                                     (dec-max-severity record) 0 100)))
      (when e (push e errors)))
    ;; Finding count matches actual
    (unless (= (dec-finding-count record) (length (dec-findings record)))
      (push (make-validation-error
             :field "finding-count"
             :code :reference
             :message (format nil "Finding count ~D != actual ~D"
                              (dec-finding-count record)
                              (length (dec-findings record)))
             :severity :error)
            errors))
    ;; Reasoning non-empty
    (let ((e (validate-required-string "reasoning" (dec-reasoning record))))
      (when e (push e errors)))
    (nreverse errors)))

;;; ─── Corpus Validator ───

(declaim (ftype (function (regression-corpus) list) validate-corpus-artifact))
(defun validate-corpus-artifact (corpus)
  "Validate a regression corpus as a well-formed artifact."
  (declare (optimize (safety 3)))
  (let ((errors '()))
    ;; Corpus-id required
    (let ((e (validate-required-string "corpus-id" (rc-corpus-id corpus))))
      (when e (push e errors)))
    ;; Must have streams
    (when (null (rc-streams corpus))
      (push (make-validation-error
             :field "streams"
             :code :empty-payload
             :message "Corpus has no streams"
             :severity :error)
            errors))
    ;; Fixture/live sig counts match
    (unless (= (length (rc-fixture-sigs corpus))
               (length (rc-live-sigs corpus)))
      (push (make-validation-error
             :field "sigs"
             :code :reference
             :message (format nil "Fixture sig count ~D != live sig count ~D"
                              (length (rc-fixture-sigs corpus))
                              (length (rc-live-sigs corpus)))
             :severity :error)
            errors))
    ;; Validate each stream
    (dolist (s (rc-streams corpus))
      (let ((stream-errors (validate-stream-artifact s)))
        (dolist (e stream-errors)
          (push (make-validation-error
                 :field (format nil "streams[~A].~A"
                                (rstr-stream-id s) (ve-field e))
                 :code (ve-code e)
                 :message (ve-message e)
                 :severity (ve-severity e))
                errors))))
    (nreverse errors)))

;;; ─── Composable Validation Pipeline ───

(declaim (ftype (function (list) (values boolean list &optional))
                summarize-validation))
(defun summarize-validation (errors)
  "Summarize validation errors. Returns (VALUES valid-p errors).
   valid-p is NIL if any :fatal error exists."
  (declare (optimize (safety 3)))
  (let ((has-fatal (some (lambda (e) (eq (ve-severity e) :fatal)) errors)))
    (values (not has-fatal) errors)))

(declaim (ftype (function (artifact-envelope &optional t) artifact-envelope)
                run-artifact-validation))
(defun run-artifact-validation (envelope &optional payload)
  "Run full validation on an artifact envelope + optional payload.
   Returns updated envelope with valid-p and errors set."
  (declare (optimize (safety 3)))
  (let ((all-errors (validate-envelope envelope)))
    ;; Validate payload by kind if provided
    (when payload
      (let ((payload-errors
              (etypecase payload
                (replay-stream (validate-stream-artifact payload))
                (decision-record (validate-decision-artifact payload))
                (regression-corpus (validate-corpus-artifact payload)))))
        (setf all-errors (nconc all-errors payload-errors))))
    (multiple-value-bind (valid-p _) (summarize-validation all-errors)
      (declare (ignore _))
      (make-artifact-envelope
       :artifact-id (ae-artifact-id envelope)
       :kind (ae-kind envelope)
       :version (ae-version envelope)
       :created-at (ae-created-at envelope)
       :source (ae-source envelope)
       :checksum (ae-checksum envelope)
       :payload-size (ae-payload-size envelope)
       :valid-p valid-p
       :errors all-errors))))
