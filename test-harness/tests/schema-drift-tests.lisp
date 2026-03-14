;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; schema-drift-tests.lisp — Tests for schema drift detector

(in-package #:orrery/harness-tests)

(define-test schema-drift-tests)

;;; ─── Payload parser ───

(define-test (schema-drift-tests parse-simple-object)
  (let ((fields (orrery/adapter:parse-payload-fields
                 "{\"status\":\"ok\",\"count\":42}")))
    (is = 2 (length fields))
    (is eq :string (cdr (assoc "status" fields :test #'string=)))
    (is eq :integer (cdr (assoc "count" fields :test #'string=)))))

(define-test (schema-drift-tests parse-all-types)
  (let ((fields (orrery/adapter:parse-payload-fields
                 "{\"s\":\"x\",\"n\":1,\"b\":true,\"a\":[],\"o\":{},\"z\":null}")))
    (is eq :string (cdr (assoc "s" fields :test #'string=)))
    (is eq :integer (cdr (assoc "n" fields :test #'string=)))
    (is eq :boolean (cdr (assoc "b" fields :test #'string=)))
    (is eq :array (cdr (assoc "a" fields :test #'string=)))
    (is eq :object (cdr (assoc "o" fields :test #'string=)))
    (is eq :null (cdr (assoc "z" fields :test #'string=)))))

(define-test (schema-drift-tests parse-empty-object)
  (let ((fields (orrery/adapter:parse-payload-fields "{}")))
    (is = 0 (length fields))))

(define-test (schema-drift-tests parse-non-json)
  (let ((fields (orrery/adapter:parse-payload-fields "not json")))
    (true (null fields))))

;;; ─── Drift detection ───

(define-test (schema-drift-tests no-drift-matching-payload)
  (let* ((schema orrery/adapter:*health-schema*)
         (fields (orrery/adapter:parse-payload-fields "{\"status\":\"ok\"}"))
         (report (orrery/adapter:detect-drift schema fields)))
    (true (orrery/adapter:dr-compatible-p report))
    (is eq :info (orrery/adapter:dr-max-severity report))
    (is = 0 (length (orrery/adapter:dr-findings report)))))

(define-test (schema-drift-tests missing-required-field)
  (let* ((schema orrery/adapter:*health-schema*)
         (fields (orrery/adapter:parse-payload-fields "{\"version\":\"1.0\"}"))
         (report (orrery/adapter:detect-drift schema fields)))
    (false (orrery/adapter:dr-compatible-p report))
    (is eq :breaking (orrery/adapter:dr-max-severity report))
    (true (find :missing-field (orrery/adapter:dr-findings report)
                :key #'orrery/adapter:df-drift-type))))

(define-test (schema-drift-tests type-mismatch)
  (let* ((schema orrery/adapter:*health-schema*)
         (fields (orrery/adapter:parse-payload-fields "{\"status\":42}"))
         (report (orrery/adapter:detect-drift schema fields)))
    (false (orrery/adapter:dr-compatible-p report))
    (is eq :degrading (orrery/adapter:dr-max-severity report))
    (true (find :type-mismatch (orrery/adapter:dr-findings report)
                :key #'orrery/adapter:df-drift-type))))

(define-test (schema-drift-tests extra-field-cosmetic)
  (let* ((schema orrery/adapter:*health-schema*)
         (fields (orrery/adapter:parse-payload-fields
                  "{\"status\":\"ok\",\"extra\":true}"))
         (report (orrery/adapter:detect-drift schema fields)))
    (true (orrery/adapter:dr-compatible-p report))
    (true (find :extra-field (orrery/adapter:dr-findings report)
                :key #'orrery/adapter:df-drift-type))
    (true (find :info (orrery/adapter:dr-findings report)
                :key #'orrery/adapter:df-severity))))

;;; ─── Batch detection ───

(define-test (schema-drift-tests detect-all-with-payloads)
  (let ((reports (orrery/adapter:detect-all-drift
                  orrery/adapter:*standard-schemas*
                  '(("health" . "{\"status\":\"ok\"}")
                    ("sessions-list" . "{\"sessions\":[]}")))))
    (is = 2 (length reports))
    (true (every #'orrery/adapter:dr-compatible-p reports))))

(define-test (schema-drift-tests detect-all-missing-payload)
  (let ((reports (orrery/adapter:detect-all-drift
                  orrery/adapter:*standard-schemas*
                  '(("health" . "{\"status\":\"ok\"}")))))
    ;; sessions-list has no payload → breaking
    (let ((missing (find "sessions-list" reports
                         :key #'orrery/adapter:dr-endpoint-name :test #'string=)))
      (false (orrery/adapter:dr-compatible-p missing))
      (is eq :breaking (orrery/adapter:dr-max-severity missing)))))

;;; ─── JSON reporter ───

(define-test (schema-drift-tests json-compatible-report)
  (let* ((schema orrery/adapter:*health-schema*)
         (fields (orrery/adapter:parse-payload-fields "{\"status\":\"ok\"}"))
         (report (orrery/adapter:detect-drift schema fields))
         (json (orrery/adapter:drift-report-to-json report)))
    (true (search "\"compatible\":true" json))
    (true (search "\"endpoint\":\"health\"" json))
    (true (search "\"findings\":[]" json))))

(define-test (schema-drift-tests json-drift-report)
  (let* ((schema orrery/adapter:*health-schema*)
         (fields (orrery/adapter:parse-payload-fields "{\"version\":\"1.0\"}"))
         (report (orrery/adapter:detect-drift schema fields))
         (json (orrery/adapter:drift-report-to-json report)))
    (true (search "\"compatible\":false" json))
    (true (search "\"drift_type\":\"missing-field\"" json))
    (true (search "\"severity\":\"breaking\"" json))))
