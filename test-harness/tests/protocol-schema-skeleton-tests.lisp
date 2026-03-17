;;; protocol-schema-skeleton-tests.lisp

(in-package #:orrery/harness-tests)

(define-test protocol-schema-skeleton-suite
  (define-test default-schema-pass
    (let* ((s (orrery/protocol-schema:default-schema :web :status "1.0"))
           (errs (orrery/protocol-schema:validate-payload
                  s
                  (list (cons :id "x") (cons :timestamp 1) (cons :state :ok)))))
      (is = 0 (length errs))
      (true (search "\"field_count\"" (orrery/protocol-schema:schema->json s)))))

  (define-test missing-field-fails
    (let* ((s (orrery/protocol-schema:default-schema :tui :status "1.0"))
           (errs (orrery/protocol-schema:validate-payload s (list (cons :id "x")))))
      (true (> (length errs) 0)))))
