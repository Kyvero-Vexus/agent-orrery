;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; ui-protocol-schema-tests.lisp — Tests for typed UI protocol schema layer
;;; Bead: agent-orrery-4ua

(in-package #:orrery/harness-tests)

(define-test ui-protocol-schema-suite

  (define-test default-schema-construction
    (let ((schema (orrery/adapter:make-default-ui-protocol-schema :web :status "1.0")))
      (is eq :web (orrery/adapter:ups-surface schema))
      (is eq :status (orrery/adapter:ups-kind schema))
      (is string= "1.0" (orrery/adapter:ups-version schema))
      (true (> (length (orrery/adapter:ups-fields schema)) 0))))

  (define-test validate-payload-pass
    (let* ((schema (orrery/adapter:make-default-ui-protocol-schema :tui :status "1.0"))
           (payload (list (cons :id "s1")
                          (cons :timestamp 123)
                          (cons :state :ok)
                          (cons :summary "stable")))
           (errors (orrery/adapter:validate-payload-against-ui-schema schema payload)))
      (is = 0 (length errors))))

  (define-test validate-payload-missing-field
    (let* ((schema (orrery/adapter:make-default-ui-protocol-schema :tui :status "1.0"))
           (payload (list (cons :id "s1")
                          (cons :timestamp 123)))
           (errors (orrery/adapter:validate-payload-against-ui-schema schema payload)))
      (true (find "missing-field:STATE" errors :test #'string=))))

  (define-test validate-payload-type-mismatch
    (let* ((schema (orrery/adapter:make-default-ui-protocol-schema :web :status "1.0"))
           (payload (list (cons :id "s1")
                          (cons :timestamp "bad")
                          (cons :state :ok)))
           (errors (orrery/adapter:validate-payload-against-ui-schema schema payload)))
      (true (find "type-mismatch:TIMESTAMP" errors :test #'string=))))

  (define-test migration-transformer
    (let* ((m (orrery/adapter:make-ui-schema-migration
               :surface :web
               :kind :event
               :from-version "1.0"
               :to-version "1.1"
               :transformer (lambda (payload)
                              (append payload (list (cons :version "1.1"))))))
           (out (orrery/adapter:migrate-ui-payload m (list (cons :event-id "e1")))))
      (true (assoc :version out :test #'eq))
      (is string= "1.1" (cdr (assoc :version out :test #'eq)))))

  (define-test json-projections
    (let* ((schema (orrery/adapter:make-default-ui-protocol-schema :mcclim :analytics "2.0"))
           (m (orrery/adapter:make-ui-schema-migration
               :surface :mcclim :kind :analytics :from-version "1.0" :to-version "2.0"))
           (sjson (orrery/adapter:ui-protocol-schema->json schema))
           (mjson (orrery/adapter:ui-schema-migration->json m)))
      (true (search "\"surface\":\"mcclim\"" sjson))
      (true (search "\"version\":\"2.0\"" sjson))
      (true (search "\"from\":\"1.0\"" mjson))
      (true (search "\"to\":\"2.0\"" mjson)))))
