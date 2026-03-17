;;; package.lisp — typed protocol schema package

(defpackage #:orrery/protocol-schema
  (:use #:cl)
  (:export
   ;; types
   #:protocol-surface #:protocol-kind
   #:schema-field #:schema-field-p #:make-schema-field
   #:sf-name #:sf-required-p #:sf-type-tag #:sf-default-value
   #:schema-spec #:schema-spec-p #:make-schema-spec
   #:ss-surface #:ss-kind #:ss-version #:ss-fields
   ;; validators/serializers
   #:default-schema #:validate-payload #:schema->json))
