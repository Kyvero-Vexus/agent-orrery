;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; contract-harness-tests.lisp — Tests for live-runtime contract harness

(in-package #:orrery/harness-tests)

(define-test contract-harness-tests)

;;; ─── Target validation ───

(define-test (contract-harness-tests fixture-target-always-valid)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test fixture"))
         (check (orrery/adapter:validate-runtime-target target)))
    (is eq :pass (orrery/adapter:cc-verdict check))))

(define-test (contract-harness-tests live-target-empty-url-fails)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "empty"))
         (check (orrery/adapter:validate-runtime-target target)))
    (is eq :fail (orrery/adapter:cc-verdict check))
    (true (search "ORRERY_OPENCLAW_BASE_URL" (orrery/adapter:cc-message check)))))

(define-test (contract-harness-tests live-target-html-gateway-fails)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "http://127.0.0.1:18789"
                  :description "local gateway"))
         (check (orrery/adapter:validate-runtime-target target)))
    (is eq :fail (orrery/adapter:cc-verdict check))
    (true (search "HTML" (orrery/adapter:cc-message check)))))

(define-test (contract-harness-tests live-target-valid-url-passes)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "http://api.example.com:7474"
                  :description "remote API"))
         (check (orrery/adapter:validate-runtime-target target)))
    (is eq :pass (orrery/adapter:cc-verdict check))))

(define-test (contract-harness-tests probe-empty-url-fails)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :probe-only :base-url ""))
         (check (orrery/adapter:validate-runtime-target target)))
    (is eq :fail (orrery/adapter:cc-verdict check))))

;;; ─── Contract harness ───

(define-test (contract-harness-tests fixture-all-contracts-pass)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "fixture"))
         (result (orrery/adapter:run-contract-harness
                  target orrery/adapter:*standard-contracts*)))
    (true (orrery/adapter:harness-result-p result))
    (is eq :pass (orrery/adapter:chr-overall-verdict result))
    ;; 1 target validation + 4 contracts = 5 pass
    (is = 5 (orrery/adapter:chr-pass-count result))
    (is = 0 (orrery/adapter:chr-fail-count result))))

(define-test (contract-harness-tests live-invalid-skips-contracts)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "invalid"))
         (result (orrery/adapter:run-contract-harness
                  target orrery/adapter:*standard-contracts*)))
    (is eq :fail (orrery/adapter:chr-overall-verdict result))
    (is = 1 (orrery/adapter:chr-fail-count result))  ; target validation
    (is = 4 (orrery/adapter:chr-skip-count result)))) ; all contracts skipped

(define-test (contract-harness-tests html-gateway-skips-contracts)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "http://127.0.0.1:18789"
                  :description "html gateway"))
         (result (orrery/adapter:run-contract-harness
                  target orrery/adapter:*standard-contracts*)))
    (is eq :fail (orrery/adapter:chr-overall-verdict result))
    ;; Clearly identifies the blocker
    (true (some (lambda (c) (search "HTML" (orrery/adapter:cc-message c)))
                (orrery/adapter:chr-checks result)))))

(define-test (contract-harness-tests empty-contracts-list)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "fixture"))
         (result (orrery/adapter:run-contract-harness target '())))
    (is eq :pass (orrery/adapter:chr-overall-verdict result))
    (is = 1 (orrery/adapter:chr-pass-count result))))  ; only target validation

;;; ─── JSON output ───

(define-test (contract-harness-tests json-output-structure)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (result (orrery/adapter:run-contract-harness
                  target orrery/adapter:*standard-contracts*))
         (json (orrery/adapter:harness-result-to-json result)))
    (true (stringp json))
    (true (search "\"overall_verdict\":\"pass\"" json))
    (true (search "\"pass_count\":5" json))
    (true (search "\"target_profile\":\"fixture\"" json))
    (true (search "\"checks\":[" json))))

(define-test (contract-harness-tests json-fail-output)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (result (orrery/adapter:run-contract-harness
                  target orrery/adapter:*standard-contracts*))
         (json (orrery/adapter:harness-result-to-json result)))
    (true (search "\"overall_verdict\":\"fail\"" json))
    (true (search "\"fail_count\":1" json))))

;;; ─── Artifact write ───

(define-test (contract-harness-tests write-artifact)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (result (orrery/adapter:run-contract-harness
                  target orrery/adapter:*standard-contracts*))
         (dir (pathname (format nil "/tmp/orrery-harness-~D/" (get-universal-time))))
         (path (orrery/adapter:write-harness-artifact result dir)))
    (true (probe-file path))
    (true (search "contract-harness-result" (namestring path)))))
