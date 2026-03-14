;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-orchestrator-tests.lisp — Tests for gate-resolution orchestrator

(in-package #:orrery/harness-tests)

(define-test gate-orchestrator-tests)

;;; ─── Pass resolution ───

(define-test (gate-orchestrator-tests pass-closes-gate)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :pass :s1-verdict :gate-pass
                  :target-profile :fixture :conformance-summary "ok"
                  :drift-compatible-p t :blockers '() :notes "ok"
                  :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record)))
    (is eq :close-gate (orrery/adapter:rp-primary-action plan))
    (is = 5 (length (orrery/adapter:rp-remediation-steps plan)))))

(define-test (gate-orchestrator-tests pass-unblocks-epics)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :pass :s1-verdict :gate-pass
                  :target-profile :fixture :conformance-summary "ok"
                  :drift-compatible-p t :blockers '() :notes "ok"
                  :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record)))
    (true (member "epic-3" (orrery/adapter:rp-unblock-targets plan) :test #'string=))
    (true (member "epic-4" (orrery/adapter:rp-unblock-targets plan) :test #'string=))
    (true (member "epic-5" (orrery/adapter:rp-unblock-targets plan) :test #'string=))))

(define-test (gate-orchestrator-tests pass-step-dependencies)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :pass :s1-verdict :gate-pass
                  :target-profile :fixture :conformance-summary "ok"
                  :drift-compatible-p t :blockers '() :notes "ok"
                  :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record))
         (steps (orrery/adapter:rp-remediation-steps plan)))
    ;; First step has no deps
    (is = 0 (length (orrery/adapter:rs-depends-on (first steps))))
    ;; Signal steps depend on unblock
    (let ((sig3 (find "signal-epic3" steps
                      :key #'orrery/adapter:rs-step-id :test #'string=)))
      (true (member "unblock-eb0.2" (orrery/adapter:rs-depends-on sig3)
                    :test #'string=)))))

(define-test (gate-orchestrator-tests pass-no-blocker-report)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :pass :s1-verdict :gate-pass
                  :target-profile :fixture :conformance-summary "ok"
                  :drift-compatible-p t :blockers '() :notes "ok"
                  :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record)))
    (is string= "" (orrery/adapter:rp-blocker-report plan))))

;;; ─── Blocked-external resolution ───

(define-test (gate-orchestrator-tests blocked-external-emits-report)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :blocked-external
                  :s1-verdict :gate-fail-transport :target-profile :live
                  :conformance-summary "bad" :drift-compatible-p t
                  :blockers (list (orrery/adapter:make-blocker-entry
                                   :blocker-class :transport
                                   :reason-code "s1-transport"
                                   :description "no endpoint"
                                   :remediation-hint "set URL"))
                  :notes "blocked" :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record)))
    (is eq :emit-blocker-report (orrery/adapter:rp-primary-action plan))
    (true (search "BLOCKER REPORT" (orrery/adapter:rp-blocker-report plan)))
    (is = 0 (length (orrery/adapter:rp-unblock-targets plan)))))

(define-test (gate-orchestrator-tests blocked-external-steps)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :blocked-external
                  :s1-verdict :gate-fail-transport :target-profile :live
                  :conformance-summary "bad" :drift-compatible-p t
                  :blockers (list (orrery/adapter:make-blocker-entry
                                   :blocker-class :transport
                                   :reason-code "s1-transport"
                                   :description "no endpoint"
                                   :remediation-hint "set URL"))
                  :notes "blocked" :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record)))
    (true (plusp (length (orrery/adapter:rp-remediation-steps plan))))
    (true (every (lambda (s) (eq :external-action (orrery/adapter:rs-action-type s)))
                 (orrery/adapter:rp-remediation-steps plan)))))

;;; ─── Contract remediation ───

(define-test (gate-orchestrator-tests contract-opens-chain)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :fail
                  :s1-verdict :gate-fail-schema :target-profile :live
                  :conformance-summary "schema fail" :drift-compatible-p nil
                  :blockers (list (orrery/adapter:make-blocker-entry
                                   :blocker-class :schema-drift
                                   :reason-code "drift"
                                   :description "missing field"
                                   :remediation-hint "fix schema"))
                  :notes "fail" :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record)))
    (is eq :open-remediation-chain (orrery/adapter:rp-primary-action plan))
    (true (plusp (length (orrery/adapter:rp-remediation-steps plan))))))

;;; ─── Escalation ───

(define-test (gate-orchestrator-tests escalate-on-inconclusive)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :inconclusive
                  :s1-verdict :gate-skip :target-profile :live
                  :conformance-summary "?" :drift-compatible-p t
                  :blockers '() :notes "?" :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record)))
    (is eq :escalate-to-human (orrery/adapter:rp-primary-action plan))
    (is = 1 (length (orrery/adapter:rp-remediation-steps plan)))))

;;; ─── JSON output ───

(define-test (gate-orchestrator-tests json-pass-structure)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :pass :s1-verdict :gate-pass
                  :target-profile :fixture :conformance-summary "ok"
                  :drift-compatible-p t :blockers '() :notes "ok"
                  :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record))
         (json (orrery/adapter:resolution-plan-to-json plan)))
    (true (search "\"primary_action\":\"close-gate\"" json))
    (true (search "\"unblock_targets\":[" json))
    (true (search "\"epic-3\"" json))
    (true (search "\"remediation_steps\":[" json))))

(define-test (gate-orchestrator-tests json-blocked-structure)
  (let* ((bundle (orrery/adapter:make-evidence-bundle
                  :gate-id "test" :decision :blocked-external
                  :s1-verdict :gate-fail-transport :target-profile :live
                  :conformance-summary "bad" :drift-compatible-p t
                  :blockers (list (orrery/adapter:make-blocker-entry
                                   :blocker-class :transport
                                   :reason-code "s1-transport"
                                   :description "no endpoint"
                                   :remediation-hint "set URL"))
                  :notes "blocked" :timestamp (get-universal-time)))
         (record (orrery/adapter:decide-s1-gate bundle))
         (plan (orrery/adapter:orchestrate-resolution record))
         (json (orrery/adapter:resolution-plan-to-json plan)))
    (true (search "\"primary_action\":\"emit-blocker-report\"" json))
    (true (search "\"unblock_targets\":[]" json))
    (true (search "\"action_type\":\"external-action\"" json))))
