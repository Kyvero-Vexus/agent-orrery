;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-retention-policy-evaluator-tests.lisp — tests for jwv2
;;; Bead: agent-orrery-jwv2

(in-package #:orrery/harness-tests)

(define-test playwright-retention-policy-evaluator-suite)

;;; ── Unit tests for retention policy ADTs ──────────────────────────────────────

(define-test (playwright-retention-policy-evaluator-suite make-s1-s6-retention-policy)
  (let ((policy (orrery/adapter:make-s1-s6-retention-policy
                 :scenario-id "S1"
                 :retention-window 86400
                 :required-kinds '(:screenshot :trace)
                 :command-fingerprint 12345)))
    (true (orrery/adapter:s1-s6-retention-policy-p policy))
    (is string= "S1" (orrery/adapter:srp-scenario-id policy))
    (is = 86400 (orrery/adapter:srp-retention-window policy))
    (is equal '(:screenshot :trace) (orrery/adapter:srp-required-kinds policy))
    (is = 12345 (orrery/adapter:srp-command-fingerprint policy))))

(define-test (playwright-retention-policy-evaluator-suite make-retention-evaluation-result)
  (let ((result (orrery/adapter:make-retention-evaluation-result
                 :scenario-id "S2"
                 :pass-p t
                 :age-secs 3600
                 :within-window-p t
                 :kinds-present '(:screenshot :trace)
                 :kinds-missing nil
                 :command-match-p t
                 :provenance-edge-p t
                 :detail "All artifacts present")))
    (true (orrery/adapter:retention-evaluation-result-p result))
    (is string= "S2" (orrery/adapter:rer-scenario-id result))
    (true (orrery/adapter:rer-pass-p result))
    (is = 3600 (orrery/adapter:rer-age-secs result))))

(define-test (playwright-retention-policy-evaluator-suite make-s1-s6-retention-report)
  (let ((report (orrery/adapter:make-s1-s6-retention-report
                 :run-id "test-run-001"
                 :command "cd e2e && ./run-e2e.sh"
                 :command-fingerprint 99999
                 :pass-p t
                 :evaluated-count 6
                 :failed-scenarios nil
                 :results nil
                 :timestamp 1700000000)))
    (true (orrery/adapter:s1-s6-retention-report-p report))
    (is string= "test-run-001" (orrery/adapter:srr-run-id report))
    (is = 6 (orrery/adapter:srr-evaluated-count report))
    (true (orrery/adapter:srr-pass-p report))))

;;; ── JSON serialization tests ──────────────────────────────────────────────────

(define-test (playwright-retention-policy-evaluator-suite retention-evaluation-result->json-smoke)
  (let* ((result (orrery/adapter:make-retention-evaluation-result
                  :scenario-id "S3"
                  :pass-p nil
                  :age-secs 100000
                  :within-window-p nil
                  :kinds-present '(:screenshot)
                  :kinds-missing '(:trace)
                  :command-match-p t
                  :provenance-edge-p nil
                  :detail "Missing trace artifact"))
         (json (orrery/adapter:retention-evaluation-result->json result)))
    (true (stringp json))
    (true (search "\"scenario_id\"" json))
    (true (search "S3" json))
    (true (search "false" json))))

(define-test (playwright-retention-policy-evaluator-suite s1-s6-retention-report->json-smoke)
  (let* ((report (orrery/adapter:make-s1-s6-retention-report
                  :run-id "run-42"
                  :command "./run-e2e.sh"
                  :command-fingerprint 1
                  :pass-p nil
                  :evaluated-count 6
                  :failed-scenarios '("S1" "S3")
                  :results nil
                  :timestamp 0))
         (json (orrery/adapter:s1-s6-retention-report->json report)))
    (true (stringp json))
    (true (search "\"run_id\"" json))
    (true (search "run-42" json))
    (true (search "\"failed_scenarios\"" json))))

;;; ── Canonical command validator test ──────────────────────────────────────────

(define-test (playwright-retention-policy-evaluator-suite canonical-playwright-command-p/retention-valid)
  (true (orrery/adapter:canonical-playwright-command-p/retention "cd e2e && ./run-e2e.sh"))
  (true (orrery/adapter:canonical-playwright-command-p/retention "bash run-e2e.sh")))

(define-test (playwright-retention-policy-evaluator-suite canonical-playwright-command-p/retention-invalid)
  (false (orrery/adapter:canonical-playwright-command-p/retention "random-command"))
  (false (orrery/adapter:canonical-playwright-command-p/retention "")))

;;; ── Fail-closed behavior tests ────────────────────────────────────────────────

(define-test (playwright-retention-policy-evaluator-suite evaluate-scenario-retention-fail-missing-trace)
  ;; Missing :trace artifact should fail
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S1"
                 '(:screenshot)           ; missing :trace
                 0                        ; age
                 86400                    ; window
                 t)))                     ; prov edge
    (false (orrery/adapter:rer-pass-p result))
    (is equal '(:trace) (orrery/adapter:rer-kinds-missing result))))

(define-test (playwright-retention-policy-evaluator-suite evaluate-scenario-retention-pass-all-present)
  ;; All artifacts present should pass
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S2"
                 '(:screenshot :trace)
                 0
                 86400
                 t)))
    (true (orrery/adapter:rer-pass-p result))
    (is equal nil (orrery/adapter:rer-kinds-missing result))))

(define-test (playwright-retention-policy-evaluator-suite evaluate-scenario-retention-fail-stale-artifact)
  ;; Stale artifact (age > window) should fail
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S3"
                 '(:screenshot :trace)
                 200000                   ; age > 86400 window
                 86400
                 t)))
    (false (orrery/adapter:rer-pass-p result))
    (false (orrery/adapter:rer-within-window-p result))))
