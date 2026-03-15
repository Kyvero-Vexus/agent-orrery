;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; schema-compat.lisp — Typed CL event schema compatibility checker
;;;
;;; Validates normalized event/snapshot schemas across fixture and live
;;; adapter outputs with machine-readable mismatch reports.

(in-package #:orrery/adapter)

;;; ─── Field Signature ───

(deftype field-kind ()
  "JSON-like field type classification."
  '(member :string :integer :boolean :list :object :null :unknown))

(defstruct (field-sig
             (:constructor make-field-sig
                 (&key name field-type required-p path))
             (:conc-name fs-))
  "Signature of one field in a schema."
  (name "" :type string)
  (field-type :unknown :type field-kind)
  (required-p nil :type boolean)
  (path "" :type string))

;;; ─── Schema Signature ───

(defstruct (schema-sig
             (:constructor make-schema-sig
                 (&key endpoint version fields timestamp))
             (:conc-name ss-))
  "Complete schema signature for an endpoint."
  (endpoint "" :type string)
  (version "" :type string)
  (fields '() :type list)
  (timestamp 0 :type (integer 0)))

;;; ─── Mismatch Entry ───

(deftype compat-severity ()
  "Severity of a schema mismatch."
  '(member :info :degrading :breaking))

(deftype compat-category ()
  "Category of a schema mismatch."
  '(member :missing-field :extra-field :type-change :nullability-change))

(defstruct (compat-mismatch
             (:constructor make-compat-mismatch
                 (&key path category fixture-value live-value
                       severity remediation))
             (:conc-name cm-))
  "One schema mismatch between fixture and live."
  (path "" :type string)
  (category :missing-field :type compat-category)
  (fixture-value "" :type string)
  (live-value "" :type string)
  (severity :info :type compat-severity)
  (remediation "" :type string))

;;; ─── Compat Report ───

(defstruct (compat-report
             (:constructor make-compat-report
                 (&key endpoint compatible-p mismatches max-severity
                       fixture-sig live-sig timestamp))
             (:conc-name cr-))
  "Schema compatibility report for one endpoint."
  (endpoint "" :type string)
  (compatible-p t :type boolean)
  (mismatches '() :type list)
  (max-severity :info :type compat-severity)
  (fixture-sig (make-schema-sig) :type schema-sig)
  (live-sig (make-schema-sig) :type schema-sig)
  (timestamp 0 :type (integer 0)))

;;; ─── Field Comparison ───

(declaim (ftype (function (field-sig field-sig) (or null compat-mismatch))
                compare-field))
(defun compare-field (fixture-field live-field)
  "Compare two field signatures. Returns NIL if compatible, else a mismatch."
  (declare (optimize (safety 3)))
  (cond
    ;; Type changed
    ((not (eq (fs-field-type fixture-field) (fs-field-type live-field)))
     (make-compat-mismatch
      :path (fs-path fixture-field)
      :category :type-change
      :fixture-value (symbol-name (fs-field-type fixture-field))
      :live-value (symbol-name (fs-field-type live-field))
      :severity (if (fs-required-p fixture-field) :breaking :degrading)
      :remediation (format nil "Field ~A type changed from ~A to ~A"
                           (fs-name fixture-field)
                           (fs-field-type fixture-field)
                           (fs-field-type live-field))))
    ;; Nullability changed (was required, now optional)
    ((and (fs-required-p fixture-field) (not (fs-required-p live-field)))
     (make-compat-mismatch
      :path (fs-path fixture-field)
      :category :nullability-change
      :fixture-value "required"
      :live-value "optional"
      :severity :degrading
      :remediation (format nil "Field ~A changed from required to optional"
                           (fs-name fixture-field))))
    ;; Compatible
    (t nil)))

;;; ─── Schema Comparison ───

(declaim (ftype (function (schema-sig schema-sig) list) compare-schemas))
(defun compare-schemas (fixture-sig live-sig)
  "Compare fixture and live schema signatures. Returns list of mismatches."
  (declare (optimize (safety 3)))
  (let ((mismatches '())
        (fixture-fields (ss-fields fixture-sig))
        (live-fields (ss-fields live-sig)))
    ;; Check each fixture field against live
    (dolist (ff fixture-fields)
      (let ((lf (find (fs-name ff) live-fields
                       :key #'fs-name :test #'string=)))
        (if lf
            ;; Field exists in both — compare
            (let ((mm (compare-field ff lf)))
              (when mm (push mm mismatches)))
            ;; Missing in live
            (push (make-compat-mismatch
                   :path (fs-path ff)
                   :category :missing-field
                   :fixture-value (format nil "~A (~A)" (fs-name ff) (fs-field-type ff))
                   :live-value "(absent)"
                   :severity (if (fs-required-p ff) :breaking :degrading)
                   :remediation (format nil "Field ~A missing from live schema" (fs-name ff)))
                  mismatches))))
    ;; Check for extra fields in live
    (dolist (lf live-fields)
      (unless (find (fs-name lf) fixture-fields
                    :key #'fs-name :test #'string=)
        (push (make-compat-mismatch
               :path (fs-path lf)
               :category :extra-field
               :fixture-value "(absent)"
               :live-value (format nil "~A (~A)" (fs-name lf) (fs-field-type lf))
               :severity :info
               :remediation (format nil "Extra field ~A in live schema — no action needed" (fs-name lf)))
              mismatches)))
    (nreverse mismatches)))

;;; ─── Severity Aggregation ───

(declaim (ftype (function (list) compat-severity) max-mismatch-severity))
(defun max-mismatch-severity (mismatches)
  "Return the highest severity among mismatches."
  (declare (optimize (safety 3)))
  (let ((has-breaking nil)
        (has-degrading nil))
    (dolist (m mismatches)
      (ecase (cm-severity m)
        (:breaking (setf has-breaking t))
        (:degrading (setf has-degrading t))
        (:info nil)))
    (cond (has-breaking :breaking)
          (has-degrading :degrading)
          (t :info))))

;;; ─── Report Builder ───

(declaim (ftype (function (schema-sig schema-sig &key (:timestamp (integer 0)))
                          compat-report)
                check-schema-compatibility))
(defun check-schema-compatibility (fixture-sig live-sig &key (timestamp 0))
  "Run full schema compatibility check. Pure function."
  (declare (optimize (safety 3)))
  (let* ((mismatches (compare-schemas fixture-sig live-sig))
         (max-sev (if mismatches (max-mismatch-severity mismatches) :info))
         (compat (not (eq max-sev :breaking))))
    (make-compat-report
     :endpoint (ss-endpoint fixture-sig)
     :compatible-p compat
     :mismatches mismatches
     :max-severity max-sev
     :fixture-sig fixture-sig
     :live-sig live-sig
     :timestamp timestamp)))

;;; ─── Multi-Endpoint Batch ───

(declaim (ftype (function (list list &key (:timestamp (integer 0))) list)
                check-all-schemas))
(defun check-all-schemas (fixture-sigs live-sigs &key (timestamp 0))
  "Check compatibility for all matched endpoint pairs.
   Returns list of compat-reports. Unmatched endpoints get :missing-field reports."
  (declare (optimize (safety 3)))
  (let ((reports '()))
    (dolist (fs fixture-sigs)
      (let ((ls (find (ss-endpoint fs) live-sigs
                      :key #'ss-endpoint :test #'string=)))
        (push (if ls
                  (check-schema-compatibility fs ls :timestamp timestamp)
                  (make-compat-report
                   :endpoint (ss-endpoint fs)
                   :compatible-p nil
                   :mismatches (list (make-compat-mismatch
                                      :path (ss-endpoint fs)
                                      :category :missing-field
                                      :fixture-value "entire schema"
                                      :live-value "(absent)"
                                      :severity :breaking
                                      :remediation "Endpoint missing from live adapter"))
                   :max-severity :breaking
                   :fixture-sig fs
                   :live-sig (make-schema-sig :endpoint (ss-endpoint fs))
                   :timestamp timestamp))
              reports)))
    (nreverse reports)))
