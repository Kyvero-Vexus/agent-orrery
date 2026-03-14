;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; schema-drift.lisp — Typed protocol schema drift detector
;;;
;;; Compares live-runtime payloads against normalized protocol contracts
;;; and emits actionable incompatibility reports before runtime startup.
;;; Modular: separate parsers, validators, and reporters.

(in-package #:orrery/adapter)

;;; ─── Schema Types ───

(deftype field-type ()
  '(member :string :integer :boolean :array :object :null :unknown))

(deftype drift-severity ()
  '(member :breaking :degrading :cosmetic :info))

;;; ─── Schema Field ───

(defstruct (schema-field
             (:constructor make-schema-field
                 (&key name expected-type required-p))
             (:conc-name sf-))
  "Expected field in a protocol schema."
  (name "" :type string)
  (expected-type :string :type field-type)
  (required-p t :type boolean))

;;; ─── Protocol Schema ───

(defstruct (protocol-schema
             (:constructor make-protocol-schema
                 (&key endpoint-name version fields))
             (:conc-name ps-))
  "Schema contract for one endpoint."
  (endpoint-name "" :type string)
  (version "" :type string)
  (fields '() :type list))

;;; ─── Drift Finding ───

(defstruct (drift-finding
             (:constructor make-drift-finding
                 (&key field-name drift-type severity message remediation))
             (:conc-name df-))
  "One detected schema drift."
  (field-name "" :type string)
  (drift-type :missing-field :type keyword)
  (severity :breaking :type drift-severity)
  (message "" :type string)
  (remediation "" :type string))

;;; ─── Drift Report ───

(defstruct (drift-report
             (:constructor make-drift-report
                 (&key endpoint-name schema-version findings
                       compatible-p max-severity timestamp))
             (:conc-name dr-))
  "Complete drift report for one endpoint."
  (endpoint-name "" :type string)
  (schema-version "" :type string)
  (findings '() :type list)
  (compatible-p t :type boolean)
  (max-severity :info :type drift-severity)
  (timestamp 0 :type integer))

;;; ─── Standard Schemas ───

(defparameter *health-schema*
  (make-protocol-schema
   :endpoint-name "health"
   :version "1.0"
   :fields (list (make-schema-field :name "status" :expected-type :string :required-p t)))
  "Expected schema for /health endpoint.")

(defparameter *sessions-list-schema*
  (make-protocol-schema
   :endpoint-name "sessions-list"
   :version "1.0"
   :fields (list (make-schema-field :name "sessions" :expected-type :array :required-p t)))
  "Expected schema for sessions list endpoint.")

(defparameter *standard-schemas*
  (list *health-schema* *sessions-list-schema*)
  "All standard protocol schemas.")

;;; ─── Payload Parser ───

(declaim (ftype (function (string) (values list &optional))
                parse-payload-fields)
         (ftype (function (protocol-schema list) (values drift-report &optional))
                detect-drift)
         (ftype (function (list list) (values list &optional))
                detect-all-drift)
         (ftype (function (drift-report) (values string &optional))
                drift-report-to-json))

(defun %classify-json-type (value-start)
  "Classify JSON value type from first character."
  (declare (type character value-start))
  (case value-start
    (#\" :string)
    ((#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9 #\-) :integer)
    (#\t :boolean)
    (#\f :boolean)
    (#\[ :array)
    (#\{ :object)
    (#\n :null)
    (otherwise :unknown)))

(defun parse-payload-fields (json-body)
  "Parse top-level field names and types from a JSON object body.
   Returns alist of (name . field-type)."
  (declare (type string json-body))
  (let ((fields '())
        (len (length json-body))
        (i 0))
    ;; Skip to first {
    (loop while (and (< i len) (char/= #\{ (char json-body i))) do (incf i))
    (when (>= i len) (return-from parse-payload-fields nil))
    (incf i) ; skip {
    ;; Simple top-level field extraction
    (loop while (< i len)
          do (let ((quote-pos (position #\" json-body :start i)))
               (unless quote-pos (return))
               (let ((name-end (position #\" json-body :start (1+ quote-pos))))
                 (unless name-end (return))
                 (let ((field-name (subseq json-body (1+ quote-pos) name-end)))
                   ;; Find colon then value
                   (let ((colon (position #\: json-body :start (1+ name-end))))
                     (unless colon (return))
                     ;; Skip whitespace after colon
                     (let ((val-start (1+ colon)))
                       (loop while (and (< val-start len)
                                        (member (char json-body val-start)
                                                '(#\Space #\Tab #\Newline)))
                             do (incf val-start))
                       (when (< val-start len)
                         (push (cons field-name
                                     (%classify-json-type (char json-body val-start)))
                               fields))
                       ;; Advance past this field's value (simplified: find next comma or })
                       (setf i (or (position #\, json-body :start val-start)
                                   len))
                       (when (< i len) (incf i))))))))
    (nreverse fields)))

;;; ─── Drift Detector ───

(defun %severity-rank (sev)
  (declare (type drift-severity sev))
  (case sev (:breaking 3) (:degrading 2) (:cosmetic 1) (:info 0)))

(defun detect-drift (schema payload-fields)
  "Compare parsed payload fields against protocol schema.
   Returns drift-report with findings."
  (declare (type protocol-schema schema) (type list payload-fields))
  (let ((findings '())
        (max-sev :info))
    ;; Check for missing required fields
    (dolist (field (ps-fields schema))
      (let ((found (assoc (sf-name field) payload-fields :test #'string=)))
        (cond
          ((null found)
           (let ((sev (if (sf-required-p field) :breaking :cosmetic)))
             (when (> (%severity-rank sev) (%severity-rank max-sev))
               (setf max-sev sev))
             (push (make-drift-finding
                    :field-name (sf-name field)
                    :drift-type :missing-field
                    :severity sev
                    :message (format nil "Required field '~A' missing from response"
                                    (sf-name field))
                    :remediation (format nil "Ensure endpoint returns '~A' field"
                                         (sf-name field)))
                   findings)))
          ;; Type mismatch
          ((not (eq (sf-expected-type field) (cdr found)))
           (let ((sev :degrading))
             (when (> (%severity-rank sev) (%severity-rank max-sev))
               (setf max-sev sev))
             (push (make-drift-finding
                    :field-name (sf-name field)
                    :drift-type :type-mismatch
                    :severity sev
                    :message (format nil "Field '~A': expected ~A, got ~A"
                                    (sf-name field) (sf-expected-type field) (cdr found))
                    :remediation (format nil "Field '~A' should be type ~A"
                                         (sf-name field) (sf-expected-type field)))
                   findings))))))
    ;; Check for extra fields (cosmetic)
    (dolist (pf payload-fields)
      (unless (find (car pf) (ps-fields schema) :key #'sf-name :test #'string=)
        (push (make-drift-finding
               :field-name (car pf)
               :drift-type :extra-field
               :severity :info
               :message (format nil "Unexpected field '~A' in response" (car pf))
               :remediation "")
              findings)))
    (let ((compat (null (remove-if
                          (lambda (f) (member (df-severity f) '(:cosmetic :info)))
                          findings))))
      (make-drift-report
       :endpoint-name (ps-endpoint-name schema)
       :schema-version (ps-version schema)
       :findings (nreverse findings)
       :compatible-p compat
       :max-severity max-sev
       :timestamp (get-universal-time)))))

(defun detect-all-drift (schemas payload-alist)
  "Run drift detection across all schemas.
   PAYLOAD-ALIST: ((endpoint-name . json-body-string) ...)"
  (declare (type list schemas payload-alist))
  (let ((reports '()))
    (dolist (schema schemas)
      (let ((payload (cdr (assoc (ps-endpoint-name schema) payload-alist
                                 :test #'string=))))
        (if payload
            (push (detect-drift schema (parse-payload-fields payload)) reports)
            (push (make-drift-report
                   :endpoint-name (ps-endpoint-name schema)
                   :schema-version (ps-version schema)
                   :findings (list (make-drift-finding
                                    :field-name ""
                                    :drift-type :no-payload
                                    :severity :breaking
                                    :message "No payload captured for this endpoint"
                                    :remediation "Capture transcript for this endpoint"))
                   :compatible-p nil
                   :max-severity :breaking
                   :timestamp (get-universal-time))
                  reports))))
    (nreverse reports)))

;;; ─── JSON Reporter ───

(defun drift-report-to-json (report)
  "Serialize drift report to deterministic JSON."
  (declare (type drift-report report))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"endpoint\":" s)
    (emit-json-string (dr-endpoint-name report) s)
    (write-string ",\"schema_version\":" s)
    (emit-json-string (dr-schema-version report) s)
    (write-string ",\"compatible\":" s)
    (write-string (if (dr-compatible-p report) "true" "false") s)
    (write-string ",\"max_severity\":" s)
    (emit-json-string (string-downcase (symbol-name (dr-max-severity report))) s)
    (write-string ",\"findings\":[" s)
    (let ((first t))
      (dolist (f (dr-findings report))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"field\":" s)
        (emit-json-string (df-field-name f) s)
        (write-string ",\"drift_type\":" s)
        (emit-json-string (string-downcase (symbol-name (df-drift-type f))) s)
        (write-string ",\"severity\":" s)
        (emit-json-string (string-downcase (symbol-name (df-severity f))) s)
        (write-string ",\"message\":" s)
        (emit-json-string (df-message f) s)
        (write-string ",\"remediation\":" s)
        (emit-json-string (df-remediation f) s)
        (write-string "}" s)))
    (write-string "]}" s)))
