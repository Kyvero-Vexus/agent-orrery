;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; ui-protocol-boundary-tests.lisp — Tests for typed UI protocol boundary
;;; Bead: agent-orrery-sdk

(in-package #:orrery/harness-tests)

(define-test ui-protocol-boundary-suite

  (define-test message-id-deterministic
    (is string=
        "tui-analytics-1000-2"
        (orrery/adapter:make-ui-message-id :tui :analytics 1000 2)))

  (define-test make-message-roundtrip
    (let ((msg (orrery/adapter:make-ui-message*
                :web :audit 2000 7
                (list (cons :session-id "s1")
                      (cons :severity :warning)))))
      (is string= "web-audit-2000-7" (orrery/adapter:uim-id msg))
      (is eq :web (orrery/adapter:uim-surface msg))
      (is eq :audit (orrery/adapter:uim-kind msg))))

  (define-test validate-message-success
    (let* ((msg (orrery/adapter:make-ui-message*
                 :tui :status 1 1 (list (cons :state :ok) (cons :uptime 42))))
           (contract (orrery/adapter:make-ui-contract
                      :surface :tui
                      :kind :status
                      :required-fields '(:state :uptime)
                      :schema-version "1.0"))
           (errors (orrery/adapter:validate-ui-message msg contract)))
      (is = 0 (length errors))))

  (define-test validate-message-failures
    (let* ((msg (orrery/adapter:make-ui-message*
                 :web :status 1 1 (list (cons :state :ok))))
           (contract (orrery/adapter:make-ui-contract
                      :surface :tui
                      :kind :analytics
                      :required-fields '(:state :uptime)
                      :schema-version "1.0"))
           (errors (orrery/adapter:validate-ui-message msg contract)))
      (true (find "surface-mismatch" errors :test #'string=))
      (true (find "kind-mismatch" errors :test #'string=))
      (true (find "missing-field:UPTIME" errors :test #'string=))))

  (define-test project-ui-error
    (let ((err (orrery/adapter:project-ui-error
                :transport "ERR_TIMEOUT" "request timed out")))
      (is eq :transport (orrery/adapter:uie-kind err))
      (true (orrery/adapter:uie-recoverable-p err))))

  (define-test json-shapes
    (let* ((msg (orrery/adapter:make-ui-message* :tui :status 10 1 (list (cons :state :ok))))
           (contract (orrery/adapter:make-ui-contract
                      :surface :tui :kind :status :required-fields '(:state) :schema-version "1.0"))
           (err (orrery/adapter:project-ui-error :validation "ERR_SCHEMA" "bad payload"))
           (hook (orrery/adapter:make-ui-replay-hook
                  :hook-id "hk-1" :surface :tui
                  :deterministic-command "make e2e-tui"
                  :artifact-dir "test-results/tui-artifacts"
                  :seed 42 :enabled-p t)))
      (true (search "\"deterministic_key\"" (orrery/adapter:ui-message->json msg)))
      (true (search "\"required_fields\"" (orrery/adapter:ui-contract->json contract)))
      (true (search "\"recoverable\":true" (orrery/adapter:ui-error->json err)))
      (true (search "\"hook_id\":\"hk-1\"" (orrery/adapter:ui-replay-hook->json hook))))))
