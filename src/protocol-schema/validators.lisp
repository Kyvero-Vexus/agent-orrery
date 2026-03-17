;;; validators.lisp

(in-package #:orrery/protocol-schema)

(declaim
 (ftype (function (protocol-surface protocol-kind &optional string) (values schema-spec &optional)) default-schema)
 (ftype (function (schema-spec list) (values list &optional)) validate-payload))

(defun %default-fields (kind)
  (ecase kind
    (:status (list (make-schema-field :name :id :type-tag :string)
                   (make-schema-field :name :timestamp :type-tag :integer)
                   (make-schema-field :name :state :type-tag :keyword)))
    (:session (list (make-schema-field :name :session-id :type-tag :string)
                    (make-schema-field :name :agent :type-tag :string)
                    (make-schema-field :name :model :type-tag :string)
                    (make-schema-field :name :status :type-tag :keyword)))
    (:cron (list (make-schema-field :name :name :type-tag :string)
                 (make-schema-field :name :status :type-tag :keyword)))
    (:health (list (make-schema-field :name :component :type-tag :string)
                   (make-schema-field :name :status :type-tag :keyword)))
    (:alert (list (make-schema-field :name :id :type-tag :string)
                  (make-schema-field :name :severity :type-tag :keyword)))
    (:audit (list (make-schema-field :name :seq :type-tag :integer)
                  (make-schema-field :name :hash :type-tag :string)))
    (:analytics (list (make-schema-field :name :total-sessions :type-tag :integer)))
    (:capacity (list (make-schema-field :name :zone :type-tag :string)))
    (:cost (list (make-schema-field :name :recommended-model :type-tag :string)))
    (:command (list (make-schema-field :name :command-id :type-tag :string)))
    (:event (list (make-schema-field :name :event-id :type-tag :string)))))

(defun default-schema (surface kind &optional (version "1.0"))
  (declare (type protocol-surface surface) (type protocol-kind kind) (type string version))
  (make-schema-spec :surface surface :kind kind :version version :fields (%default-fields kind)))

(defun %matches-tag-p (v tag)
  (ecase tag
    (:string (stringp v))
    (:integer (integerp v))
    (:keyword (keywordp v))))

(defun validate-payload (schema payload)
  (declare (type schema-spec schema) (type list payload))
  (let ((errors nil))
    (dolist (f (ss-fields schema))
      (let ((e (assoc (sf-name f) payload :test #'eq)))
        (cond
          ((and (sf-required-p f) (null e))
           (push (format nil "missing-field:~A" (sf-name f)) errors))
          (e
           (unless (%matches-tag-p (cdr e) (sf-type-tag f))
             (push (format nil "type-mismatch:~A" (sf-name f)) errors))))))
    (nreverse errors)))
