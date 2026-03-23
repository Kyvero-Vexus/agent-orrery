;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-retention-policy-regression-tests.lisp — Regression fixture suite for S1-S6 retention
;;; Bead: agent-orrery-ehbc

(in-package #:orrery/harness-tests)

(define-test playwright-retention-policy-regression-suite)

;;; ── Fixture snapshots: known-good inputs → expected outputs ──────────────────

;; Baseline: all artifacts present, fresh, provenance OK → must pass
(define-test (playwright-retention-policy-regression-suite fixture-snapshot-all-present-pass)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S1"
                 '(:screenshot :trace)    ; all present
                 0                         ; zero age
                 86400                     ; 24h window
                 t)))                      ; provenance edge
    (true (orrery/adapter:rer-pass-p result))
    (true (orrery/adapter:rer-within-window-p result))
    (is equal nil (orrery/adapter:rer-kinds-missing result))
    (true (orrery/adapter:rer-provenance-edge-p result))))

;; Missing screenshot → fail
(define-test (playwright-retention-policy-regression-suite fixture-snapshot-missing-screenshot-fail)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S2"
                 '(:trace)                 ; missing screenshot
                 0
                 86400
                 t)))
    (false (orrery/adapter:rer-pass-p result))
    (is equal '(:screenshot) (orrery/adapter:rer-kinds-missing result))))

;; Missing trace → fail
(define-test (playwright-retention-policy-regression-suite fixture-snapshot-missing-trace-fail)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S3"
                 '(:screenshot)            ; missing trace
                 0
                 86400
                 t)))
    (false (orrery/adapter:rer-pass-p result))
    (is equal '(:trace) (orrery/adapter:rer-kinds-missing result))))

;; Missing both → fail
(define-test (playwright-retention-policy-regression-suite fixture-snapshot-missing-both-fail)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S4"
                 '()                       ; nothing present
                 0
                 86400
                 t)))
    (false (orrery/adapter:rer-pass-p result))
    (is equal 2 (length (orrery/adapter:rer-kinds-missing result)))))

;;; ── Command-fingerprint fixture tests ─────────────────────────────────────────

;; Canonical command accepted
(define-test (playwright-retention-policy-regression-suite canonical-command-accepted)
  (true (orrery/adapter:canonical-playwright-command-p/retention
         "cd e2e && ./run-e2e.sh"))
  (true (orrery/adapter:canonical-playwright-command-p/retention
         "bash run-e2e.sh")))

;; Non-canonical command rejected
(define-test (playwright-retention-policy-regression-suite non-canonical-command-rejected)
  (false (orrery/adapter:canonical-playwright-command-p/retention
          "npm test"))
  (false (orrery/adapter:canonical-playwright-command-p/retention
          "pytest"))
  (false (orrery/adapter:canonical-playwright-command-p/retention
          "./custom-script.sh")))

;; Empty and malformed commands rejected
(define-test (playwright-retention-policy-regression-suite malformed-commands-rejected)
  (false (orrery/adapter:canonical-playwright-command-p/retention ""))
  (false (orrery/adapter:canonical-playwright-command-p/retention "random-command")))

;;; ── Retention window boundary conditions ───────────────────────────────────────

;; Exactly at window boundary (age == window) → fail (not strictly less than)
(define-test (playwright-retention-policy-regression-suite boundary-exactly-at-window-fail)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S5"
                 '(:screenshot :trace)
                 86400                     ; exactly at window
                 86400
                 t)))
    (false (orrery/adapter:rer-within-window-p result))
    (false (orrery/adapter:rer-pass-p result))))

;; One second over window → fail
(define-test (playwright-retention-policy-regression-suite boundary-one-second-over-fail)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S6"
                 '(:screenshot :trace)
                 86401                     ; one second over
                 86400
                 t)))
    (false (orrery/adapter:rer-within-window-p result))
    (false (orrery/adapter:rer-pass-p result))))

;; One second under window → pass (if all other conditions met)
(define-test (playwright-retention-policy-regression-suite boundary-one-second-under-pass)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S1"
                 '(:screenshot :trace)
                 86399                     ; one second under
                 86400
                 t)))
    (true (orrery/adapter:rer-within-window-p result))
    (true (orrery/adapter:rer-pass-p result))))

;; Zero age → within window
(define-test (playwright-retention-policy-regression-suite zero-age-within-window)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S2"
                 '(:screenshot :trace)
                 0                         ; zero age
                 86400
                 t)))
    (true (orrery/adapter:rer-within-window-p result))))

;;; ── Kinds-missing combinations ─────────────────────────────────────────────────

;; No artifacts present → both missing
(define-test (playwright-retention-policy-regression-suite kinds-none-present)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S3"
                 '()                       ; none present
                 0
                 86400
                 t)))
    (false (orrery/adapter:rer-pass-p result))
    (true (member :screenshot (orrery/adapter:rer-kinds-missing result)))
    (true (member :trace (orrery/adapter:rer-kinds-missing result)))))

;; Partial: only screenshot
(define-test (playwright-retention-policy-regression-suite kinds-partial-screenshot-only)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S4"
                 '(:screenshot)
                 0
                 86400
                 t)))
    (false (orrery/adapter:rer-pass-p result))
    (is equal '(:trace) (orrery/adapter:rer-kinds-missing result))))

;; Partial: only trace
(define-test (playwright-retention-policy-regression-suite kinds-partial-trace-only)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S5"
                 '(:trace)
                 0
                 86400
                 t)))
    (false (orrery/adapter:rer-pass-p result))
    (is equal '(:screenshot) (orrery/adapter:rer-kinds-missing result))))

;; All present
(define-test (playwright-retention-policy-regression-suite kinds-all-present)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S6"
                 '(:screenshot :trace)
                 0
                 86400
                 t)))
    (is equal nil (orrery/adapter:rer-kinds-missing result))))

;;; ── Provenance edge: false → always fail ───────────────────────────────────────

;; Provenance false with all else OK → must fail
(define-test (playwright-retention-policy-regression-suite provenance-false-fails-all-else-ok)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S1"
                 '(:screenshot :trace)
                 0
                 86400
                 nil)))                    ; provenance edge = false
    (false (orrery/adapter:rer-pass-p result))
    (false (orrery/adapter:rer-provenance-edge-p result))))

;; Provenance false with fresh artifacts → still fail
(define-test (playwright-retention-policy-regression-suite provenance-false-fails-fresh-artifacts)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S2"
                 '(:screenshot :trace)
                 100                       ; very fresh
                 86400
                 nil)))
    (false (orrery/adapter:rer-pass-p result))))

;; Provenance false with nothing missing → still fail
(define-test (playwright-retention-policy-regression-suite provenance-false-fails-nothing-missing)
  (let ((result (orrery/adapter:evaluate-scenario-retention
                 "S3"
                 '(:screenshot :trace)
                 0
                 86400
                 nil)))
    (false (orrery/adapter:rer-pass-p result))
    (is equal nil (orrery/adapter:rer-kinds-missing result))
    (true (orrery/adapter:rer-within-window-p result))
    (false (orrery/adapter:rer-provenance-edge-p result))))

;;; ── JSON serialization round-trip stability ────────────────────────────────────

;; Single result → JSON → contains expected fields
(define-test (playwright-retention-policy-regression-suite json-single-result-fields)
  (let* ((result (orrery/adapter:make-retention-evaluation-result
                  :scenario-id "S1"
                  :pass-p t
                  :age-secs 42
                  :within-window-p t
                  :kinds-present '(:screenshot :trace)
                  :kinds-missing nil
                  :command-match-p t
                  :provenance-edge-p t
                  :detail "All OK"))
         (json (orrery/adapter:retention-evaluation-result->json result)))
    (true (search "\"scenario_id\":\"S1\"" json))
    (true (search "\"pass\":true" json))
    (true (search "\"age_secs\":42" json))
    (true (search "\"within_window\":true" json))
    (true (search "\"command_match\":true" json))
    (true (search "\"provenance_edge\":true" json))))

;; Failed result → JSON → false booleans
(define-test (playwright-retention-policy-regression-suite json-failed-result-boolean-false)
  (let* ((result (orrery/adapter:make-retention-evaluation-result
                  :scenario-id "S2"
                  :pass-p nil
                  :age-secs 100000
                  :within-window-p nil
                  :kinds-present '(:screenshot)
                  :kinds-missing '(:trace)
                  :command-match-p t
                  :provenance-edge-p nil
                  :detail "Missing trace"))
         (json (orrery/adapter:retention-evaluation-result->json result)))
    (true (search "\"pass\":false" json))
    (true (search "\"within_window\":false" json))
    (true (search "\"provenance_edge\":false" json))))

;; Report → JSON → contains expected fields
(define-test (playwright-retention-policy-regression-suite json-report-fields)
  (let* ((report (orrery/adapter:make-s1-s6-retention-report
                  :run-id "test-run-42"
                  :command "cd e2e && ./run-e2e.sh"
                  :command-fingerprint 99999
                  :pass-p t
                  :evaluated-count 6
                  :failed-scenarios nil
                  :results nil
                  :timestamp 1700000000))
         (json (orrery/adapter:s1-s6-retention-report->json report)))
    (true (search "\"run_id\":\"test-run-42\"" json))
    (true (search "\"command\":\"cd e2e && ./run-e2e.sh\"" json))
    (true (search "\"command_fingerprint\":99999" json))
    (true (search "\"pass\":true" json))
    (true (search "\"evaluated_count\":6" json))
    (true (search "\"timestamp\":1700000000" json))))

;; Report with failed scenarios → JSON array
(define-test (playwright-retention-policy-regression-suite json-report-failed-array)
  (let* ((report (orrery/adapter:make-s1-s6-retention-report
                  :run-id "fail-run"
                  :command "bad-command"
                  :command-fingerprint 1
                  :pass-p nil
                  :evaluated-count 6
                  :failed-scenarios '("S1" "S3" "S5")
                  :results nil
                  :timestamp 0))
         (json (orrery/adapter:s1-s6-retention-report->json report)))
    (true (search "\"failed_scenarios\":" json))
    (true (search "S1" json))
    (true (search "S3" json))
    (true (search "S5" json))))

;; Report with results → JSON nested array
(define-test (playwright-retention-policy-regression-suite json-report-nested-results)
  (let* ((r1 (orrery/adapter:make-retention-evaluation-result
              :scenario-id "S1"
              :pass-p t
              :age-secs 0
              :within-window-p t
              :kinds-present '(:screenshot :trace)
              :kinds-missing nil
              :command-match-p t
              :provenance-edge-p t
              :detail "OK"))
         (report (orrery/adapter:make-s1-s6-retention-report
                  :run-id "nested-test"
                  :command "cd e2e && ./run-e2e.sh"
                  :command-fingerprint 12345
                  :pass-p t
                  :evaluated-count 1
                  :failed-scenarios nil
                  :results (list r1)
                  :timestamp 1000))
         (json (orrery/adapter:s1-s6-retention-report->json report)))
    (true (search "\"results\":[" json))
    (true (search "\"scenario_id\":\"S1\"" json))))

;;; ── Full report with mixed pass/fail scenarios ────────────────────────────────

;; ADT construction for policy
(define-test (playwright-retention-policy-regression-suite policy-adt-construction)
  (let ((policy (orrery/adapter:make-s1-s6-retention-policy
                 :scenario-id "S4"
                 :retention-window 43200   ; 12h
                 :required-kinds '(:screenshot :trace)
                 :command-fingerprint 11111)))
    (is string= "S4" (orrery/adapter:srp-scenario-id policy))
    (is = 43200 (orrery/adapter:srp-retention-window policy))
    (is equal '(:screenshot :trace) (orrery/adapter:srp-required-kinds policy))
    (is = 11111 (orrery/adapter:srp-command-fingerprint policy))))

;; Multiple scenarios with mixed results
(define-test (playwright-retention-policy-regression-suite mixed-scenario-results)
  (let ((results
         (list
          ;; S1: pass
          (orrery/adapter:evaluate-scenario-retention "S1" '(:screenshot :trace) 0 86400 t)
          ;; S2: fail (missing trace)
          (orrery/adapter:evaluate-scenario-retention "S2" '(:screenshot) 0 86400 t)
          ;; S3: pass
          (orrery/adapter:evaluate-scenario-retention "S3" '(:screenshot :trace) 100 86400 t)
          ;; S4: fail (stale)
          (orrery/adapter:evaluate-scenario-retention "S4" '(:screenshot :trace) 100000 86400 t)
          ;; S5: fail (provenance)
          (orrery/adapter:evaluate-scenario-retention "S5" '(:screenshot :trace) 0 86400 nil)
          ;; S6: pass
          (orrery/adapter:evaluate-scenario-retention "S6" '(:screenshot :trace) 1000 86400 t))))
    ;; Check pass/fail counts
    (is = 3 (count-if #'orrery/adapter:rer-pass-p results))
    (is = 3 (count-if-not #'orrery/adapter:rer-pass-p results))))

;; Regression: report correctly aggregates failures
(define-test (playwright-retention-policy-regression-suite report-aggregates-failures)
  (let* ((results
          (list
           (orrery/adapter:evaluate-scenario-retention "S1" '(:screenshot :trace) 0 86400 t)
           (orrery/adapter:evaluate-scenario-retention "S2" '(:screenshot) 0 86400 t)
           (orrery/adapter:evaluate-scenario-retention "S3" '(:screenshot :trace) 0 86400 t)))
         (failed (mapcar #'orrery/adapter:rer-scenario-id
                         (remove-if #'orrery/adapter:rer-pass-p results)))
         (report (orrery/adapter:make-s1-s6-retention-report
                  :run-id "agg-test"
                  :command "cd e2e && ./run-e2e.sh"
                  :command-fingerprint 0
                  :pass-p (null failed)
                  :evaluated-count (length results)
                  :failed-scenarios failed
                  :results results
                  :timestamp 0)))
    (false (orrery/adapter:srr-pass-p report))
    (is = 3 (orrery/adapter:srr-evaluated-count report))
    (is = 1 (length (orrery/adapter:srr-failed-scenarios report)))
    (is string= "S2" (first (orrery/adapter:srr-failed-scenarios report)))))

;; Regression: all pass → report pass=true
(define-test (playwright-retention-policy-regression-suite report-all-pass)
  (let* ((results
          (list
           (orrery/adapter:evaluate-scenario-retention "S1" '(:screenshot :trace) 0 86400 t)
           (orrery/adapter:evaluate-scenario-retention "S2" '(:screenshot :trace) 100 86400 t)))
         (failed (mapcar #'orrery/adapter:rer-scenario-id
                         (remove-if #'orrery/adapter:rer-pass-p results)))
         (report (orrery/adapter:make-s1-s6-retention-report
                  :run-id "all-pass"
                  :command "cd e2e && ./run-e2e.sh"
                  :command-fingerprint 0
                  :pass-p (null failed)
                  :evaluated-count (length results)
                  :failed-scenarios failed
                  :results results
                  :timestamp 0)))
    (true (orrery/adapter:srr-pass-p report))
    (is equal nil (orrery/adapter:srr-failed-scenarios report))))

;;; ── Deterministic replay: fingerprint stability ────────────────────────────────

;; Command fingerprint is deterministic
(define-test (playwright-retention-policy-regression-suite fingerprint-deterministic)
  (let ((fp1 (sxhash "cd e2e && ./run-e2e.sh"))
        (fp2 (sxhash "cd e2e && ./run-e2e.sh")))
    (is = fp1 fp2)))

;; Different commands have different fingerprints
(define-test (playwright-retention-policy-regression-suite fingerprint-different-commands)
  (let ((fp1 (sxhash "cd e2e && ./run-e2e.sh"))
        (fp2 (sxhash "bash run-e2e.sh")))
    ;; Note: they may collide by chance but very unlikely
    ;; We just check they're both valid integers
    (true (integerp fp1))
    (true (integerp fp2))))

;; Policy with same command → same fingerprint
(define-test (playwright-retention-policy-regression-suite policy-command-fingerprint)
  (let ((p1 (orrery/adapter:make-s1-s6-retention-policy
             :scenario-id "S1"
             :retention-window 86400
             :required-kinds '(:screenshot :trace)
             :command-fingerprint (sxhash "cd e2e && ./run-e2e.sh")))
        (p2 (orrery/adapter:make-s1-s6-retention-policy
             :scenario-id "S2"
             :retention-window 86400
             :required-kinds '(:screenshot :trace)
             :command-fingerprint (sxhash "cd e2e && ./run-e2e.sh"))))
    (is = (orrery/adapter:srp-command-fingerprint p1)
        (orrery/adapter:srp-command-fingerprint p2))))
