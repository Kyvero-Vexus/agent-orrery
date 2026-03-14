;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; conformance-matrix-tests.lisp — Tests for adapter conformance matrix

(in-package #:orrery/harness-tests)

(define-test conformance-matrix-tests)

;;; ─── Matrix building ───

(define-test (conformance-matrix-tests build-from-fixture-harness)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix harness)))
    (true (orrery/adapter:conformance-matrix-p matrix))
    (is = 5 (length (orrery/adapter:cm-entries matrix)))
    (is eq :fail-fast (orrery/adapter:cm-degradation-mode matrix))))

(define-test (conformance-matrix-tests fixture-entries-full-coverage)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix harness)))
    (true (every (lambda (e) (eq :full (orrery/adapter:ce-coverage e)))
                 (orrery/adapter:cm-entries matrix)))))

(define-test (conformance-matrix-tests empty-url-entries-missing)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix harness)))
    ;; Target validation = stub (fail), contracts = missing (skip)
    (true (some (lambda (e) (eq :stub (orrery/adapter:ce-coverage e)))
                (orrery/adapter:cm-entries matrix)))
    (true (some (lambda (e) (eq :missing (orrery/adapter:ce-coverage e)))
                (orrery/adapter:cm-entries matrix)))))

(define-test (conformance-matrix-tests custom-degradation-mode)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix
                  harness :degradation-mode :graceful)))
    (is eq :graceful (orrery/adapter:cm-degradation-mode matrix))))

;;; ─── Conformance checking ───

(define-test (conformance-matrix-tests fixture-is-conformant)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix harness))
         (result (orrery/adapter:check-conformance matrix)))
    (true (orrery/adapter:ccr-conformant-p result))
    (is = 0 (length (orrery/adapter:ccr-violations result)))))

(define-test (conformance-matrix-tests empty-url-non-conformant)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix harness))
         (result (orrery/adapter:check-conformance matrix)))
    (false (orrery/adapter:ccr-conformant-p result))
    (true (plusp (length (orrery/adapter:ccr-violations result))))
    (is eq :fail-fast (orrery/adapter:ccr-degradation-action result))))

(define-test (conformance-matrix-tests minimum-coverage-stub-lenient)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix
                  harness :minimum-coverage :stub)))
    ;; With stub minimum, only :missing entries violate
    (let ((result (orrery/adapter:check-conformance matrix)))
      ;; Still non-conformant because skipped entries are :missing
      (false (orrery/adapter:ccr-conformant-p result)))))

(define-test (conformance-matrix-tests graceful-degradation-on-failure)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix
                  harness :degradation-mode :graceful))
         (result (orrery/adapter:check-conformance matrix)))
    (is eq :graceful (orrery/adapter:ccr-degradation-action result))))

;;; ─── JSON output ───

(define-test (conformance-matrix-tests json-structure)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix harness))
         (json (orrery/adapter:conformance-matrix-to-json matrix)))
    (true (search "\"adapter_name\":" json))
    (true (search "\"degradation_mode\":\"fail-fast\"" json))
    (true (search "\"entries\":[" json))
    (true (search "\"coverage\":\"full\"" json))))

(define-test (conformance-matrix-tests json-non-conformant)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (matrix (orrery/adapter:build-conformance-matrix harness))
         (json (orrery/adapter:conformance-matrix-to-json matrix)))
    (true (search "\"coverage\":\"stub\"" json))
    (true (search "\"coverage\":\"missing\"" json))))
