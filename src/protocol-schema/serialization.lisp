;;; serialization.lisp

(in-package #:orrery/protocol-schema)

(declaim (ftype (function (schema-spec) (values string &optional)) schema->json))

(defun schema->json (schema)
  (declare (type schema-spec schema))
  (format nil
          "{\"surface\":\"~(~A~)\",\"kind\":\"~(~A~)\",\"version\":\"~A\",\"field_count\":~D}"
          (ss-surface schema)
          (ss-kind schema)
          (ss-version schema)
          (length (ss-fields schema))))
