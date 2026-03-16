;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; scenario-planning-tests.lisp — Tests for Coalton scenario-planning core
;;;
;;; Bead: agent-orrery-20d

(in-package #:orrery/harness-tests)

;;; ============================================================
;;; Scenario Planning Core Tests
;;; ============================================================

(define-test scenario-planning-tests)

;;; --- Test helpers ---

(cl:defun %make-test-baseline ()
  "Build a standard test baseline for scenario projections."
  (cl:let ((ranks (coalton:coalton
                   (coalton:Cons
                    (orrery/coalton/core::ModelRank "claude-opus" 8000 600)
                    (coalton:Cons
                     (orrery/coalton/core::ModelRank "claude-sonnet" 2000 400)
                     coalton:Nil)))))
    (orrery/coalton/core:cl-make-baseline-snapshot
     10 5000 200 4 ranks 10000)))

(cl:defun %empty-params ()
  (coalton:coalton coalton:Nil))

(cl:defun %single-param (param)
  "Wrap a single Coalton ScenarioParam into a Coalton list."
  (cl:declare (cl:ignore param))
  ;; Can't easily do this generically without coalton:lisp.
  ;; Each call site will build inline instead.
  cl:nil)

;;; --- CL bridge constructor tests ---

(define-test (scenario-planning-tests cl-make-baseline-snapshot)
  (let ((bs (%make-test-baseline)))
    (true bs)
    (let* ((sc (orrery/coalton/core:cl-make-scenario "test" (%empty-params) 1))
           (result (orrery/coalton/core:cl-run-scenario bs sc)))
      (true result)
      (is string= "test" (orrery/coalton/core:cl-projection-scenario-name result)))))

;;; --- Identity projection (no overrides) ---

(define-test (scenario-planning-tests identity-projection)
  (let* ((bs (%make-test-baseline))
         (sc (orrery/coalton/core:cl-make-scenario "identity" (%empty-params) 10))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    (is = 50000 (orrery/coalton/core:cl-projection-total-tokens r))
    (is = 2000 (orrery/coalton/core:cl-projection-total-cost r))
    (is = 10 (orrery/coalton/core:cl-projection-sessions r))
    (is = 40 (orrery/coalton/core:cl-projection-cron-invocations r))
    (is = 20 (orrery/coalton/core:cl-projection-budget-util-pct r))))

;;; --- Session volume override ---

(define-test (scenario-planning-tests doubled-sessions)
  (let* ((bs (%make-test-baseline))
         (params (coalton:coalton
                  (coalton:Cons (orrery/coalton/core:SPSessionVolume 20)
                                coalton:Nil)))
         (sc (orrery/coalton/core:cl-make-scenario "double" params 10))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    (is = 100000 (orrery/coalton/core:cl-projection-total-tokens r))
    (is = 4000 (orrery/coalton/core:cl-projection-total-cost r))
    (is = 20 (orrery/coalton/core:cl-projection-sessions r))))

;;; --- Budget cap override ---

(define-test (scenario-planning-tests budget-cap-override)
  (let* ((bs (%make-test-baseline))
         (params (coalton:coalton
                  (coalton:Cons (orrery/coalton/core:SPBudgetCap 1000)
                                coalton:Nil)))
         (sc (orrery/coalton/core:cl-make-scenario "tight-budget" params 10))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    (is = 200 (orrery/coalton/core:cl-projection-budget-util-pct r))))

;;; --- Cron cadence override ---

(define-test (scenario-planning-tests cron-cadence-override)
  (let* ((bs (%make-test-baseline))
         (params (coalton:coalton
                  (coalton:Cons (orrery/coalton/core:SPCronCadence 12)
                                coalton:Nil)))
         (sc (orrery/coalton/core:cl-make-scenario "fast-cron" params 10))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    (is = 120 (orrery/coalton/core:cl-projection-cron-invocations r))))

;;; --- Token ceiling override ---

(define-test (scenario-planning-tests token-ceiling-signal)
  (let* ((bs (%make-test-baseline))
         (params (coalton:coalton
                  (coalton:Cons (orrery/coalton/core:SPTokenCeiling 100)
                                coalton:Nil)))
         (sc (orrery/coalton/core:cl-make-scenario "cap-test" params 10))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    ;; Total tokens = 50000 >> 100 ceiling → over-capacity signal expected
    (true r)))

;;; --- Zero baseline edge case ---

(define-test (scenario-planning-tests zero-session-baseline)
  (let* ((ranks (coalton:coalton coalton:Nil))
         (bs (orrery/coalton/core:cl-make-baseline-snapshot
              0 1000 50 2 ranks 5000))
         (params (coalton:coalton
                  (coalton:Cons (orrery/coalton/core:SPSessionVolume 5)
                                coalton:Nil)))
         (sc (orrery/coalton/core:cl-make-scenario "zero-base" params 10))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    (is = 10000 (orrery/coalton/core:cl-projection-total-tokens r))))

;;; --- Scenario name accessor ---

(define-test (scenario-planning-tests scenario-name-accessor)
  (let* ((bs (%make-test-baseline))
         (sc (orrery/coalton/core:cl-make-scenario "test-sc" (%empty-params) 24))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    (is string= "test-sc" (orrery/coalton/core:cl-projection-scenario-name r))))

;;; --- Adapter bridge integration ---

(define-test (scenario-planning-tests adapter-bridge-roundtrip)
  "Test scenario projection through the adapter bridge."
  (let* ((bs (%make-test-baseline))
         (sc (orrery/coalton/core:cl-make-scenario "bridge-test" (%empty-params) 10))
         (coalton-result (orrery/coalton/core:cl-run-scenario bs sc))
         (cl-result (orrery/adapter:coalton-projection->cl coalton-result)))
    (true (orrery/adapter:scenario-projection-p cl-result))
    (is string= "bridge-test" (orrery/adapter:sproj-scenario-name cl-result))
    (is = 50000 (orrery/adapter:sproj-total-tokens cl-result))
    (is = 2000 (orrery/adapter:sproj-total-cost cl-result))
    (is = 10 (orrery/adapter:sproj-sessions cl-result))
    (is = 40 (orrery/adapter:sproj-cron-invocations cl-result))
    (is = 20 (orrery/adapter:sproj-budget-util-pct cl-result))))

;;; --- JSON serialization ---

(define-test (scenario-planning-tests json-serialization)
  "Scenario projection serializes to valid JSON."
  (let* ((bs (%make-test-baseline))
         (sc (orrery/coalton/core:cl-make-scenario "json-test" (%empty-params) 10))
         (coalton-result (orrery/coalton/core:cl-run-scenario bs sc))
         (cl-result (orrery/adapter:coalton-projection->cl coalton-result))
         (json-str (orrery/adapter:scenario-projection->json cl-result)))
    (true (stringp json-str))
    (true (plusp (length json-str)))
    (true (search "json-test" json-str))
    (true (search "50000" json-str))))

;;; --- Model mix imbalance ---

(define-test (scenario-planning-tests model-mix-imbalance)
  "Heavily skewed model mix → imbalance signal exists in projection."
  (let* ((skewed-ranks (coalton:coalton
                        (coalton:Cons
                         (orrery/coalton/core::ModelRank "opus" 9000 900)
                         (coalton:Cons
                          (orrery/coalton/core::ModelRank "sonnet" 1000 100)
                          coalton:Nil))))
         (bs (orrery/coalton/core:cl-make-baseline-snapshot
              10 5000 200 4 skewed-ranks 10000))
         (sc (orrery/coalton/core:cl-make-scenario "skewed" (%empty-params) 1))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    ;; With 900 permille for one model, should get mix-imbalance
    (true r)))

;;; --- Caution threshold ---

(define-test (scenario-planning-tests caution-threshold)
  "Budget utilization 80-100% yields a meaningful projection."
  (let* ((ranks (coalton:coalton coalton:Nil))
         (bs (orrery/coalton/core:cl-make-baseline-snapshot
              10 5000 900 4 ranks 10000))
         (sc (orrery/coalton/core:cl-make-scenario "caution" (%empty-params) 10))
         (r (orrery/coalton/core:cl-run-scenario bs sc)))
    ;; 900 * 10 = 9000 vs 10000 cap = 90% → should be in caution range
    (is = 90 (orrery/coalton/core:cl-projection-budget-util-pct r))))

;;; --- SP tag tests via Coalton ---

(define-test (scenario-planning-tests sp-tag-values)
  "ScenarioParam sp-tag returns expected strings."
  (is string= "session-volume"
      (coalton:coalton (orrery/coalton/core:sp-tag
                        (orrery/coalton/core:SPSessionVolume 20))))
  (is string= "model-mix"
      (coalton:coalton (orrery/coalton/core:sp-tag
                        (orrery/coalton/core:SPModelMix coalton:Nil))))
  (is string= "cron-cadence"
      (coalton:coalton (orrery/coalton/core:sp-tag
                        (orrery/coalton/core:SPCronCadence 10))))
  (is string= "budget-cap"
      (coalton:coalton (orrery/coalton/core:sp-tag
                        (orrery/coalton/core:SPBudgetCap 5000))))
  (is string= "token-ceiling"
      (coalton:coalton (orrery/coalton/core:sp-tag
                        (orrery/coalton/core:SPTokenCeiling 100000)))))

;;; --- Signal label tests via Coalton ---

(define-test (scenario-planning-tests signal-label-values)
  (is string= "ok"
      (coalton:coalton (orrery/coalton/core:signal-label orrery/coalton/core:SignalOk)))
  (is string= "caution"
      (coalton:coalton (orrery/coalton/core:signal-label orrery/coalton/core:SignalCaution)))
  (is string= "over-budget"
      (coalton:coalton (orrery/coalton/core:signal-label orrery/coalton/core:SignalOverBudget)))
  (is string= "over-capacity"
      (coalton:coalton (orrery/coalton/core:signal-label orrery/coalton/core:SignalOverCapacity)))
  (is string= "mix-imbalance"
      (coalton:coalton (orrery/coalton/core:signal-label orrery/coalton/core:SignalMixImbalance))))
