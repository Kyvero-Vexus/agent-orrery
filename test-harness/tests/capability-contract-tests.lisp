;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capability-contract-tests.lisp — Tests for capability contract + negotiation

(in-package #:orrery/harness-tests)

(define-test capability-contract-tests)

;;; ─── Schema validation ───

(define-test (capability-contract-tests valid-schema)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "test-adapter"
                  :adapter-version "1.0.0"
                  :protocol-version :v1
                  :endpoints (list
                              (orrery/adapter:make-endpoint-capability
                               :path "/health" :operation :health
                               :semantic :read-only :supported-p t)
                              (orrery/adapter:make-endpoint-capability
                               :path "/sessions" :operation :list-sessions
                               :semantic :read-only :supported-p t))))
         (result (orrery/adapter:validate-schema schema)))
    (true (orrery/adapter:vr-valid-p result))
    (is = 0 (length (remove-if-not
                      (lambda (i) (eq :error (orrery/adapter:vi-severity i)))
                      (orrery/adapter:vr-issues result))))))

(define-test (capability-contract-tests empty-name-fails)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name ""
                  :endpoints (list (orrery/adapter:make-endpoint-capability
                                    :path "/x" :operation :x :semantic :read-only))))
         (result (orrery/adapter:validate-schema schema)))
    (false (orrery/adapter:vr-valid-p result))
    (true (some (lambda (i) (string= "adapter-name" (orrery/adapter:vi-field i)))
                (orrery/adapter:vr-issues result)))))

(define-test (capability-contract-tests empty-path-fails)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "test"
                  :endpoints (list (orrery/adapter:make-endpoint-capability
                                    :path "" :operation :x :semantic :read-only))))
         (result (orrery/adapter:validate-schema schema)))
    (false (orrery/adapter:vr-valid-p result))))

(define-test (capability-contract-tests destructive-without-auth-warns)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "test"
                  :endpoints (list (orrery/adapter:make-endpoint-capability
                                    :path "/delete" :operation :delete
                                    :semantic :destructive :requires-auth nil))))
         (result (orrery/adapter:validate-schema schema)))
    (true (orrery/adapter:vr-valid-p result))  ; warning, not error
    (true (some (lambda (i) (eq :warning (orrery/adapter:vi-severity i)))
                (orrery/adapter:vr-issues result)))))

(define-test (capability-contract-tests duplicate-paths-warns)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "test"
                  :endpoints (list
                              (orrery/adapter:make-endpoint-capability
                               :path "/x" :operation :a :semantic :read-only)
                              (orrery/adapter:make-endpoint-capability
                               :path "/x" :operation :b :semantic :read-only))))
         (result (orrery/adapter:validate-schema schema)))
    (true (some (lambda (i)
                  (and (eq :warning (orrery/adapter:vi-severity i))
                       (search "Duplicate" (orrery/adapter:vi-message i))))
                (orrery/adapter:vr-issues result)))))

(define-test (capability-contract-tests no-endpoints-warns)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "test" :endpoints nil))
         (result (orrery/adapter:validate-schema schema)))
    (true (orrery/adapter:vr-valid-p result))  ; warning only
    (true (some (lambda (i) (eq :warning (orrery/adapter:vi-severity i)))
                (orrery/adapter:vr-issues result)))))

;;; ─── Negotiation flow ───

(define-test (capability-contract-tests negotiate-full-access)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "full"
                  :endpoints (list
                              (orrery/adapter:make-endpoint-capability
                               :path "/health" :operation :health :semantic :read-only)
                              (orrery/adapter:make-endpoint-capability
                               :path "/sessions" :operation :list-sessions :semantic :read-only))))
         (result (orrery/adapter:negotiate-capabilities schema '(:health :list-sessions))))
    (is eq :full-access (orrery/adapter:nr-outcome result))
    (is = 2 (length (orrery/adapter:nr-available-operations result)))
    (is = 0 (length (orrery/adapter:nr-denied-operations result)))))

(define-test (capability-contract-tests negotiate-partial-access)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "partial"
                  :endpoints (list
                              (orrery/adapter:make-endpoint-capability
                               :path "/health" :operation :health :semantic :read-only)
                              (orrery/adapter:make-endpoint-capability
                               :path "/sessions" :operation :list-sessions
                               :semantic :read-write :supported-p t)
                              (orrery/adapter:make-endpoint-capability
                               :path "/cron" :operation :trigger-cron
                               :semantic :read-write :supported-p nil))))
         (result (orrery/adapter:negotiate-capabilities schema '(:health :list-sessions :trigger-cron))))
    (is eq :partial-access (orrery/adapter:nr-outcome result))
    (is = 2 (length (orrery/adapter:nr-available-operations result)))
    (is = 1 (length (orrery/adapter:nr-denied-operations result)))))

(define-test (capability-contract-tests negotiate-no-access)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "none" :endpoints nil))
         (result (orrery/adapter:negotiate-capabilities schema '(:health))))
    (is eq :no-access (orrery/adapter:nr-outcome result))
    (is = 0 (length (orrery/adapter:nr-available-operations result)))))

(define-test (capability-contract-tests negotiate-elevation-tracking)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "admin"
                  :endpoints (list
                              (orrery/adapter:make-endpoint-capability
                               :path "/delete" :operation :delete-session
                               :semantic :destructive :requires-auth t :supported-p t))))
         (result (orrery/adapter:negotiate-capabilities schema '(:delete-session))))
    (is eq :full-access (orrery/adapter:nr-outcome result))
    (true (member :delete-session (orrery/adapter:nr-requires-elevation result)))))

(define-test (capability-contract-tests negotiate-empty-request)
  (let* ((schema (orrery/adapter:make-capability-schema
                  :adapter-name "test"
                  :endpoints (list (orrery/adapter:make-endpoint-capability
                                    :path "/x" :operation :x :semantic :read-only))))
         (result (orrery/adapter:negotiate-capabilities schema '())))
    (is eq :no-access (orrery/adapter:nr-outcome result))))
