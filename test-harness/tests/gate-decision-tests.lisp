;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-decision-tests.lisp — Tests for S1 gate decision engine

(in-package #:orrery/harness-tests)

(define-test gate-decision-tests)

;;; ─── Helper ───

(defun %make-pass-bundle ()
  (orrery/adapter:make-evidence-bundle
   :gate-id "s1-fixture-test"
   :target-profile :fixture
   :decision :pass
   :s1-verdict :gate-pass
   :conformance-summary "fixture: conformant"
   :drift-compatible-p t
   :blockers '()
   :artifact-shas '("abc123")
   :timestamp (get-universal-time)
   :notes "All gates passed"))

(defun %make-blocked-external-bundle ()
  (orrery/adapter:make-evidence-bundle
   :gate-id "s1-live-test"
   :target-profile :live
   :decision :blocked-external
   :s1-verdict :gate-fail-transport
   :conformance-summary "non-conformant"
   :drift-compatible-p t
   :blockers (list (orrery/adapter:make-blocker-entry
                    :blocker-class :transport
                    :reason-code "s1-transport"
                    :description "No endpoint configured"
                    :resolution :unresolved
                    :remediation-hint "Set ORRERY_OPENCLAW_BASE_URL")
                   (orrery/adapter:make-blocker-entry
                    :blocker-class :external-runtime
                    :reason-code "s1-content-type"
                    :description "HTML gateway"
                    :resolution :unresolved
                    :remediation-hint "Use JSON API endpoint"))
   :timestamp (get-universal-time)
   :notes "2 blocker(s)"))

(defun %make-contract-fail-bundle ()
  (orrery/adapter:make-evidence-bundle
   :gate-id "s1-live-schema"
   :target-profile :live
   :decision :fail
   :s1-verdict :gate-fail-schema
   :conformance-summary "schema failures"
   :drift-compatible-p nil
   :blockers (list (orrery/adapter:make-blocker-entry
                    :blocker-class :schema-drift
                    :reason-code "drift-missing-field"
                    :description "Missing status field"
                    :resolution :unresolved
                    :remediation-hint "Ensure endpoint returns status"))
   :timestamp (get-universal-time)
   :notes "1 blocker"))

(defun %make-inconclusive-bundle ()
  (orrery/adapter:make-evidence-bundle
   :gate-id "s1-unknown"
   :target-profile :live
   :decision :inconclusive
   :s1-verdict :gate-skip
   :conformance-summary "unknown"
   :drift-compatible-p t
   :blockers '()
   :timestamp (get-universal-time)
   :notes "Inconclusive"))

;;; ─── Pass branch ───

(define-test (gate-decision-tests pass-outcome)
  (let* ((bundle (%make-pass-bundle))
         (record (orrery/adapter:decide-s1-gate bundle)))
    (is eq :pass (orrery/adapter:gdr-outcome record))
    (true (orrery/adapter:gdr-can-close-gate-p record))
    (is = 0 (orrery/adapter:gdr-blocker-count record))))

(define-test (gate-decision-tests pass-next-actions)
  (let* ((bundle (%make-pass-bundle))
         (record (orrery/adapter:decide-s1-gate bundle))
         (actions (orrery/adapter:gdr-next-actions record)))
    (is = 2 (length actions))
    (true (find "close-gate" actions
                :key #'orrery/adapter:na-action-id :test #'string=))
    (true (find "unblock-epics" actions
                :key #'orrery/adapter:na-action-id :test #'string=))))

;;; ─── Blocked-external branch ───

(define-test (gate-decision-tests blocked-external-outcome)
  (let* ((bundle (%make-blocked-external-bundle))
         (record (orrery/adapter:decide-s1-gate bundle)))
    (is eq :blocked-external (orrery/adapter:gdr-outcome record))
    (false (orrery/adapter:gdr-can-close-gate-p record))
    (is = 2 (orrery/adapter:gdr-blocker-count record))))

(define-test (gate-decision-tests blocked-external-actions)
  (let* ((bundle (%make-blocked-external-bundle))
         (record (orrery/adapter:decide-s1-gate bundle))
         (actions (orrery/adapter:gdr-next-actions record))
         (ids (mapcar #'orrery/adapter:na-action-id actions)))
    (true (member "provide-endpoint" ids :test #'string=))
    (true (member "re-probe" ids :test #'string=))))

(define-test (gate-decision-tests blocked-external-reason)
  (let* ((bundle (%make-blocked-external-bundle))
         (record (orrery/adapter:decide-s1-gate bundle)))
    (true (search "external blocker" (orrery/adapter:gdr-reason record)))))

;;; ─── Blocked-contract branch ───

(define-test (gate-decision-tests blocked-contract-outcome)
  (let* ((bundle (%make-contract-fail-bundle))
         (record (orrery/adapter:decide-s1-gate bundle)))
    (is eq :blocked-contract (orrery/adapter:gdr-outcome record))
    (false (orrery/adapter:gdr-can-close-gate-p record))))

(define-test (gate-decision-tests blocked-contract-actions)
  (let* ((bundle (%make-contract-fail-bundle))
         (record (orrery/adapter:decide-s1-gate bundle))
         (actions (orrery/adapter:gdr-next-actions record))
         (ids (mapcar #'orrery/adapter:na-action-id actions)))
    (true (member "fix-schema" ids :test #'string=))
    (true (member "re-validate" ids :test #'string=))))

;;; ─── Escalate branch ───

(define-test (gate-decision-tests escalate-outcome)
  (let* ((bundle (%make-inconclusive-bundle))
         (record (orrery/adapter:decide-s1-gate bundle)))
    (is eq :escalate (orrery/adapter:gdr-outcome record))
    (false (orrery/adapter:gdr-can-close-gate-p record))))

(define-test (gate-decision-tests escalate-actions)
  (let* ((bundle (%make-inconclusive-bundle))
         (record (orrery/adapter:decide-s1-gate bundle))
         (actions (orrery/adapter:gdr-next-actions record)))
    (is = 1 (length actions))
    (is string= "investigate" (orrery/adapter:na-action-id (first actions)))))

;;; ─── JSON output ───

(define-test (gate-decision-tests json-pass)
  (let* ((bundle (%make-pass-bundle))
         (record (orrery/adapter:decide-s1-gate bundle))
         (json (orrery/adapter:gate-decision-to-json record)))
    (true (search "\"outcome\":\"pass\"" json))
    (true (search "\"can_close_gate\":true" json))
    (true (search "\"next_actions\":[" json))
    (true (search "\"action_id\":\"close-gate\"" json))))

(define-test (gate-decision-tests json-blocked)
  (let* ((bundle (%make-blocked-external-bundle))
         (record (orrery/adapter:decide-s1-gate bundle))
         (json (orrery/adapter:gate-decision-to-json record)))
    (true (search "\"outcome\":\"blocked-external\"" json))
    (true (search "\"can_close_gate\":false" json))
    (true (search "\"blocker_count\":2" json))))

(define-test (gate-decision-tests json-gate-id-linked)
  (let* ((bundle (%make-pass-bundle))
         (record (orrery/adapter:decide-s1-gate bundle)))
    (true (search "s1-fixture-test" (orrery/adapter:gdr-evidence-gate-id record)))))
