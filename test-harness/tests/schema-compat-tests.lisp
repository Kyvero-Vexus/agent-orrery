;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; schema-compat-tests.lisp — Tests for schema compatibility checker
;;;

(in-package #:orrery/harness-tests)

(define-test schema-compat)

;;; ─── Helpers ───

(defun make-test-field (name ftype &optional (required t) (path ""))
  (make-field-sig :name name :field-type ftype :required-p required
                  :path (if (string= path "") name path)))

(defun make-test-schema (endpoint &rest fields)
  (make-schema-sig :endpoint endpoint :version "1.0" :fields fields))

;;; ─── compare-field ───

(define-test (schema-compat field-identical)
  (let ((f (make-test-field "id" :string)))
    (is eq nil (compare-field f f))))

(define-test (schema-compat field-type-change-required)
  (let ((fix (make-test-field "id" :string t))
        (live (make-test-field "id" :integer t)))
    (let ((mm (compare-field fix live)))
      (true (compat-mismatch-p mm))
      (is eq :type-change (cm-category mm))
      (is eq :breaking (cm-severity mm)))))

(define-test (schema-compat field-type-change-optional)
  (let ((fix (make-test-field "meta" :string nil))
        (live (make-test-field "meta" :integer nil)))
    (let ((mm (compare-field fix live)))
      (is eq :degrading (cm-severity mm)))))

(define-test (schema-compat field-nullability-change)
  (let ((fix (make-test-field "name" :string t))
        (live (make-test-field "name" :string nil)))
    (let ((mm (compare-field fix live)))
      (is eq :nullability-change (cm-category mm))
      (is eq :degrading (cm-severity mm)))))

(define-test (schema-compat field-compatible-both-optional)
  (let ((fix (make-test-field "tag" :string nil))
        (live (make-test-field "tag" :string nil)))
    (is eq nil (compare-field fix live))))

;;; ─── compare-schemas ───

(define-test (schema-compat schemas-identical)
  (let* ((f1 (make-test-field "id" :string))
         (f2 (make-test-field "name" :string))
         (fix (make-test-schema "sessions" f1 f2))
         (live (make-test-schema "sessions" f1 f2)))
    (is = 0 (length (compare-schemas fix live)))))

(define-test (schema-compat schema-missing-field)
  (let* ((f1 (make-test-field "id" :string t))
         (f2 (make-test-field "name" :string t))
         (fix (make-test-schema "sessions" f1 f2))
         (live (make-test-schema "sessions" f1)))
    (let ((mm (compare-schemas fix live)))
      (is = 1 (length mm))
      (is eq :missing-field (cm-category (first mm)))
      (is eq :breaking (cm-severity (first mm))))))

(define-test (schema-compat schema-extra-field)
  (let* ((f1 (make-test-field "id" :string))
         (f2 (make-test-field "extra" :integer))
         (fix (make-test-schema "sessions" f1))
         (live (make-test-schema "sessions" f1 f2)))
    (let ((mm (compare-schemas fix live)))
      (is = 1 (length mm))
      (is eq :extra-field (cm-category (first mm)))
      (is eq :info (cm-severity (first mm))))))

(define-test (schema-compat schema-mixed-mismatches)
  (let* ((f-id (make-test-field "id" :string t))
         (f-name (make-test-field "name" :string t))
         (l-id (make-test-field "id" :integer t))  ;; type change
         (l-extra (make-test-field "bonus" :boolean))
         (fix (make-test-schema "events" f-id f-name))
         (live (make-test-schema "events" l-id l-extra)))
    (let ((mm (compare-schemas fix live)))
      ;; id: type-change, name: missing, bonus: extra = 3 mismatches
      (is = 3 (length mm)))))

;;; ─── max-mismatch-severity ───

(define-test (schema-compat max-severity-breaking)
  (let ((mm (list (make-compat-mismatch :severity :info)
                  (make-compat-mismatch :severity :breaking)
                  (make-compat-mismatch :severity :degrading))))
    (is eq :breaking (max-mismatch-severity mm))))

(define-test (schema-compat max-severity-degrading)
  (let ((mm (list (make-compat-mismatch :severity :info)
                  (make-compat-mismatch :severity :degrading))))
    (is eq :degrading (max-mismatch-severity mm))))

(define-test (schema-compat max-severity-info-only)
  (let ((mm (list (make-compat-mismatch :severity :info))))
    (is eq :info (max-mismatch-severity mm))))

;;; ─── check-schema-compatibility ───

(define-test (schema-compat report-compatible)
  (let* ((f (make-test-field "id" :string))
         (fix (make-test-schema "sessions" f))
         (live (make-test-schema "sessions" f))
         (report (check-schema-compatibility fix live :timestamp 42)))
    (true (cr-compatible-p report))
    (is = 0 (length (cr-mismatches report)))
    (is eq :info (cr-max-severity report))
    (is = 42 (cr-timestamp report))))

(define-test (schema-compat report-incompatible)
  (let* ((fix-f (make-test-field "id" :string t))
         (fix (make-test-schema "sessions" fix-f))
         (live (make-test-schema "sessions"))  ;; no fields
         (report (check-schema-compatibility fix live)))
    (false (cr-compatible-p report))
    (is eq :breaking (cr-max-severity report))))

(define-test (schema-compat report-degraded-compatible)
  (let* ((fix-f (make-test-field "opt" :string nil))
         (fix (make-test-schema "events" fix-f))
         (live (make-test-schema "events"))
         (report (check-schema-compatibility fix live)))
    ;; optional field missing → degrading, still compatible
    (true (cr-compatible-p report))
    (is eq :degrading (cr-max-severity report))))

;;; ─── check-all-schemas ───

(define-test (schema-compat batch-all-present)
  (let* ((f (make-test-field "id" :string))
         (fix1 (make-test-schema "sessions" f))
         (fix2 (make-test-schema "events" f))
         (live1 (make-test-schema "sessions" f))
         (live2 (make-test-schema "events" f))
         (reports (check-all-schemas (list fix1 fix2) (list live1 live2))))
    (is = 2 (length reports))
    (true (every #'cr-compatible-p reports))))

(define-test (schema-compat batch-missing-endpoint)
  (let* ((f (make-test-field "id" :string t))
         (fix (make-test-schema "sessions" f))
         (reports (check-all-schemas (list fix) '())))
    (is = 1 (length reports))
    (false (cr-compatible-p (first reports)))
    (is eq :breaking (cr-max-severity (first reports)))))

(define-test (schema-compat batch-partial-match)
  (let* ((f (make-test-field "id" :string))
         (fix1 (make-test-schema "sessions" f))
         (fix2 (make-test-schema "events" f))
         (live1 (make-test-schema "sessions" f))
         (reports (check-all-schemas (list fix1 fix2) (list live1))))
    (is = 2 (length reports))
    (true (cr-compatible-p (first reports)))
    (false (cr-compatible-p (second reports)))))
