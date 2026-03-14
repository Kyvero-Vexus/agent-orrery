;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; probe-orchestrator-tests.lisp — Tests for probe orchestrator + compat report

(in-package #:orrery/harness-tests)

(define-test probe-orchestrator-tests)

;;; ─── Failure classification ───

(define-test (probe-orchestrator-tests classify-transport)
  (let* ((check (orrery/adapter:make-contract-check
                 :endpoint-name "health" :verdict :fail
                 :message "ORRERY_OPENCLAW_BASE_URL not set"))
         (cf (orrery/adapter:classify-check-failure check)))
    (is eq :transport (orrery/adapter:cf-failure-class cf))
    (true (search "ORRERY_OPENCLAW_BASE_URL" (orrery/adapter:cf-remediation cf)))))

(define-test (probe-orchestrator-tests classify-content-type)
  (let* ((check (orrery/adapter:make-contract-check
                 :endpoint-name "sessions" :verdict :fail
                 :message "Endpoint returns HTML instead of JSON"))
         (cf (orrery/adapter:classify-check-failure check)))
    (is eq :content-type (orrery/adapter:cf-failure-class cf))))

(define-test (probe-orchestrator-tests classify-auth)
  (let* ((check (orrery/adapter:make-contract-check
                 :endpoint-name "health" :verdict :fail
                 :message "Got 401 unauthorized"))
         (cf (orrery/adapter:classify-check-failure check)))
    (is eq :auth (orrery/adapter:cf-failure-class cf))))

;;; ─── S1 probe ───

(define-test (probe-orchestrator-tests s1-fixture-passes)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (result (orrery/adapter:run-s1-probe target)))
    (is eq :gate-pass (orrery/adapter:s1-verdict result))
    (is = 0 (length (orrery/adapter:s1-classified-failures result)))
    (true (plusp (length (orrery/adapter:s1-diagnostics result))))))

(define-test (probe-orchestrator-tests s1-empty-url-fails-transport)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "empty"))
         (result (orrery/adapter:run-s1-probe target)))
    (is eq :gate-fail-transport (orrery/adapter:s1-verdict result))
    (true (plusp (length (orrery/adapter:s1-classified-failures result))))))

(define-test (probe-orchestrator-tests s1-html-gateway-fails-content)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "http://127.0.0.1:18789"
                  :description "html gateway"))
         (result (orrery/adapter:run-s1-probe target)))
    (is eq :gate-fail-content (orrery/adapter:s1-verdict result))))

(define-test (probe-orchestrator-tests s1-json-output)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (result (orrery/adapter:run-s1-probe target))
         (json (orrery/adapter:s1-gate-result-to-json result)))
    (true (search "\"verdict\":\"gate-pass\"" json))
    (true (search "\"profile\":\"fixture\"" json))
    (true (search "\"diagnostics\":" json))))

;;; ─── Compatibility report ───

(define-test (probe-orchestrator-tests compat-fixture-all-ready)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (s1 (orrery/adapter:run-s1-probe target))
         (report (orrery/adapter:generate-compatibility-report s1)))
    (is eq :ready (orrery/adapter:cr-overall-readiness report))
    (is = 4 (length (orrery/adapter:cr-signals report)))
    (is = 0 (orrery/adapter:cr-total-gaps report))))

(define-test (probe-orchestrator-tests compat-empty-url-blocked)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "empty"))
         (s1 (orrery/adapter:run-s1-probe target))
         (report (orrery/adapter:generate-compatibility-report s1)))
    (is eq :blocked (orrery/adapter:cr-overall-readiness report))
    (true (plusp (orrery/adapter:cr-total-gaps report)))))

(define-test (probe-orchestrator-tests compat-epic-signals-present)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (s1 (orrery/adapter:run-s1-probe target))
         (report (orrery/adapter:generate-compatibility-report s1))
         (names (mapcar #'orrery/adapter:pgs-epic-name
                        (orrery/adapter:cr-signals report))))
    (true (member "epic-3" names :test #'string=))
    (true (member "epic-4" names :test #'string=))
    (true (member "epic-5" names :test #'string=))
    (true (member "epic-6" names :test #'string=))))

(define-test (probe-orchestrator-tests compat-json-output)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (s1 (orrery/adapter:run-s1-probe target))
         (report (orrery/adapter:generate-compatibility-report s1))
         (json (orrery/adapter:compatibility-report-to-json report)))
    (true (search "\"overall_readiness\":\"ready\"" json))
    (true (search "\"signals\":[" json))
    (true (search "\"epic\":\"epic-3\"" json))))

(define-test (probe-orchestrator-tests compat-json-blocked)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (s1 (orrery/adapter:run-s1-probe target))
         (report (orrery/adapter:generate-compatibility-report s1))
         (json (orrery/adapter:compatibility-report-to-json report)))
    (true (search "\"overall_readiness\":\"blocked\"" json))
    (true (search "\"gaps\":[" json))))
