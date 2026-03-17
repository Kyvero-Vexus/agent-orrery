;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; ui-protocol-schema.lisp — Canonical typed UI protocol schema + migration hooks
;;; Bead: agent-orrery-4ua

(in-package #:orrery/adapter)

(deftype ui-protocol-surface () '(member :tui :web :mcclim))
(deftype ui-protocol-kind ()
  '(member :status :session :cron :health :alert :audit :analytics :capacity :cost :command :event))

(defstruct (ui-schema-field (:conc-name usf-))
  (name :id :type keyword)
  (required-p t :type boolean)
  (type-tag :string :type keyword)
  (default-value nil :type t))

(defstruct (ui-protocol-schema (:conc-name ups-))
  (surface :tui :type ui-protocol-surface)
  (kind :status :type ui-protocol-kind)
  (version "1.0" :type string)
  (fields nil :type list)
  (compat-versions nil :type list))

(defstruct (ui-schema-migration (:conc-name usm-))
  (surface :tui :type ui-protocol-surface)
  (kind :status :type ui-protocol-kind)
  (from-version "1.0" :type string)
  (to-version "1.1" :type string)
  (transformer nil :type (or null function)))

(declaim
 (ftype (function (ui-protocol-surface ui-protocol-kind &optional string) (values ui-protocol-schema &optional))
        make-default-ui-protocol-schema)
 (ftype (function (ui-protocol-schema list) (values list &optional)) validate-payload-against-ui-schema)
 (ftype (function (ui-schema-migration list) (values list &optional)) migrate-ui-payload)
 (ftype (function (ui-protocol-schema) (values string &optional)) ui-protocol-schema->json)
 (ftype (function (ui-schema-migration) (values string &optional)) ui-schema-migration->json))

(defun %kind-default-fields (kind)
  (declare (type ui-protocol-kind kind))
  (ecase kind
    (:status (list (make-ui-schema-field :name :id :type-tag :string)
                   (make-ui-schema-field :name :timestamp :type-tag :integer)
                   (make-ui-schema-field :name :state :type-tag :keyword)
                   (make-ui-schema-field :name :summary :type-tag :string :required-p nil :default-value "")))
    (:session (list (make-ui-schema-field :name :session-id :type-tag :string)
                    (make-ui-schema-field :name :agent :type-tag :string)
                    (make-ui-schema-field :name :model :type-tag :string)
                    (make-ui-schema-field :name :status :type-tag :keyword)))
    (:cron (list (make-ui-schema-field :name :name :type-tag :string)
                 (make-ui-schema-field :name :status :type-tag :keyword)
                 (make-ui-schema-field :name :next-run-at :type-tag :integer :required-p nil :default-value 0)))
    (:health (list (make-ui-schema-field :name :component :type-tag :string)
                   (make-ui-schema-field :name :status :type-tag :keyword)
                   (make-ui-schema-field :name :latency-ms :type-tag :integer :required-p nil :default-value 0)))
    (:alert (list (make-ui-schema-field :name :id :type-tag :string)
                  (make-ui-schema-field :name :severity :type-tag :keyword)
                  (make-ui-schema-field :name :title :type-tag :string)))
    (:audit (list (make-ui-schema-field :name :seq :type-tag :integer)
                  (make-ui-schema-field :name :category :type-tag :string)
                  (make-ui-schema-field :name :hash :type-tag :string)))
    (:analytics (list (make-ui-schema-field :name :total-sessions :type-tag :integer)
                      (make-ui-schema-field :name :total-cost-cents :type-tag :integer)))
    (:capacity (list (make-ui-schema-field :name :zone :type-tag :string)
                     (make-ui-schema-field :name :headroom-pct :type-tag :integer)))
    (:cost (list (make-ui-schema-field :name :recommended-model :type-tag :string)
                 (make-ui-schema-field :name :confidence :type-tag :string)))
    (:command (list (make-ui-schema-field :name :command-id :type-tag :string)
                    (make-ui-schema-field :name :name :type-tag :string)
                    (make-ui-schema-field :name :args :type-tag :list :required-p nil :default-value nil)))
    (:event (list (make-ui-schema-field :name :event-id :type-tag :string)
                  (make-ui-schema-field :name :kind :type-tag :keyword)
                  (make-ui-schema-field :name :payload :type-tag :list :required-p nil :default-value nil)))))

(defun make-default-ui-protocol-schema (surface kind &optional (version "1.0"))
  (declare (type ui-protocol-surface surface)
           (type ui-protocol-kind kind)
           (type string version))
  (make-ui-protocol-schema
   :surface surface
   :kind kind
   :version version
   :fields (%kind-default-fields kind)
   :compat-versions (list version)))

(defun %value-matches-tag-p (value tag)
  (declare (type keyword tag))
  (ecase tag
    (:string (stringp value))
    (:integer (integerp value))
    (:keyword (keywordp value))
    (:list (listp value))))

(defun validate-payload-against-ui-schema (schema payload)
  "Returns list of error strings; NIL when payload is valid."
  (declare (type ui-protocol-schema schema) (type list payload))
  (let ((errors nil))
    (dolist (f (ups-fields schema))
      (let* ((name (usf-name f))
             (required (usf-required-p f))
             (entry (assoc name payload :test #'eq)))
        (cond
          ((and required (null entry))
           (push (format nil "missing-field:~A" name) errors))
          (entry
           (unless (%value-matches-tag-p (cdr entry) (usf-type-tag f))
             (push (format nil "type-mismatch:~A" name) errors))))))
    (nreverse errors)))

(defun migrate-ui-payload (migration payload)
  "Apply MIGRATION transformer to PAYLOAD.
If no transformer exists, returns payload unchanged."
  (declare (type ui-schema-migration migration) (type list payload))
  (let ((fn (usm-transformer migration)))
    (if fn (funcall fn payload) payload)))

(defun ui-protocol-schema->json (schema)
  (declare (type ui-protocol-schema schema))
  (format nil
          "{\"surface\":\"~A\",\"kind\":\"~A\",\"version\":\"~A\",\"field_count\":~D}"
          (string-downcase (symbol-name (ups-surface schema)))
          (string-downcase (symbol-name (ups-kind schema)))
          (ups-version schema)
          (length (ups-fields schema))))

(defun ui-schema-migration->json (migration)
  (declare (type ui-schema-migration migration))
  (format nil
          "{\"surface\":\"~A\",\"kind\":\"~A\",\"from\":\"~A\",\"to\":\"~A\"}"
          (string-downcase (symbol-name (usm-surface migration)))
          (string-downcase (symbol-name (usm-kind migration)))
          (usm-from-version migration)
          (usm-to-version migration)))
