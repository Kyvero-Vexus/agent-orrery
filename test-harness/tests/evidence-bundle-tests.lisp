;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; evidence-bundle-tests.lisp — Tests for evidence bundle + blocker taxonomy

(in-package #:orrery/harness-tests)

(define-test evidence-bundle-tests)

;;; ─── Helper: run full pipeline from target ───

(defun %pipeline-from-target (target)
  "Run full pipeline: S1 probe → conformance → drift → evidence bundle."
  (let* ((s1 (orrery/adapter:run-s1-probe target))
         (harness (orrery/adapter:s1-harness-result s1))
         (matrix (if harness
                     (orrery/adapter:build-conformance-matrix harness)
                     (orrery/adapter:make-conformance-matrix)))
         (conformance (orrery/adapter:check-conformance matrix))
         ;; Drift: fixture messages aren't real JSON; skip drift for fixtures
         (fixture-p (eq :fixture (orrery/adapter:s1-profile s1)))
         (payloads (when (and harness (not fixture-p))
                     (mapcar (lambda (c)
                               (cons (orrery/adapter:cc-endpoint-name c)
                                     (orrery/adapter:cc-message c)))
                             (remove-if-not
                              (lambda (c) (eq :pass (orrery/adapter:cc-verdict c)))
                              (orrery/adapter:chr-checks harness)))))
         (drift-reports (if fixture-p
                            '()
                            (orrery/adapter:detect-all-drift
                             orrery/adapter:*standard-schemas* payloads))))
    (orrery/adapter:build-evidence-bundle
     s1 conformance drift-reports
     :artifact-shas '("abc123" "def456"))))

;;; ─── Pass path (fixture) ───

(define-test (evidence-bundle-tests fixture-pass-bundle)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (bundle (%pipeline-from-target target)))
    (true (orrery/adapter:evidence-bundle-p bundle))
    (is eq :pass (orrery/adapter:eb-decision bundle))
    (is eq :gate-pass (orrery/adapter:eb-s1-verdict bundle))
    (is = 0 (length (orrery/adapter:eb-blockers bundle)))
    (true (orrery/adapter:eb-drift-compatible-p bundle))
    (is string= "All gates passed" (orrery/adapter:eb-notes bundle))))

(define-test (evidence-bundle-tests fixture-has-artifact-shas)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (bundle (%pipeline-from-target target)))
    (is = 2 (length (orrery/adapter:eb-artifact-shas bundle)))))

(define-test (evidence-bundle-tests fixture-gate-id-format)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (bundle (%pipeline-from-target target)))
    (true (search "s1-fixture-" (orrery/adapter:eb-gate-id bundle)))))

;;; ─── Blocker path (empty URL) ───

(define-test (evidence-bundle-tests empty-url-blocked-external)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "no url"))
         (bundle (%pipeline-from-target target)))
    (is eq :blocked-external (orrery/adapter:eb-decision bundle))
    (true (plusp (length (orrery/adapter:eb-blockers bundle))))))

(define-test (evidence-bundle-tests empty-url-blocker-classes)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "no url"))
         (bundle (%pipeline-from-target target))
         (classes (mapcar #'orrery/adapter:be-blocker-class
                          (orrery/adapter:eb-blockers bundle))))
    ;; Should have transport or external-runtime blockers
    (true (or (member :transport classes)
              (member :external-runtime classes)))))

(define-test (evidence-bundle-tests empty-url-has-reason-codes)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "no url"))
         (bundle (%pipeline-from-target target)))
    (true (every (lambda (b) (plusp (length (orrery/adapter:be-reason-code b))))
                 (orrery/adapter:eb-blockers bundle)))))

(define-test (evidence-bundle-tests empty-url-has-remediation)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "no url"))
         (bundle (%pipeline-from-target target)))
    (true (every (lambda (b) (plusp (length (orrery/adapter:be-remediation-hint b))))
                 (orrery/adapter:eb-blockers bundle)))))

;;; ─── Blocker path (HTML gateway) ───

(define-test (evidence-bundle-tests html-gateway-blocked)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "http://127.0.0.1:18789"
                  :description "html gw"))
         (bundle (%pipeline-from-target target)))
    (is eq :blocked-external (orrery/adapter:eb-decision bundle))
    (true (some (lambda (b) (eq :external-runtime (orrery/adapter:be-blocker-class b)))
                (orrery/adapter:eb-blockers bundle)))))

;;; ─── Blocker classifier directly ───

(define-test (evidence-bundle-tests classify-empty-on-pass)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (s1 (orrery/adapter:run-s1-probe target))
         (harness (orrery/adapter:s1-harness-result s1))
         (matrix (orrery/adapter:build-conformance-matrix harness))
         (conformance (orrery/adapter:check-conformance matrix))
         (blockers (orrery/adapter:classify-blockers s1 conformance '())))
    (is = 0 (length blockers))))

;;; ─── JSON output ───

(define-test (evidence-bundle-tests json-pass-structure)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (bundle (%pipeline-from-target target))
         (json (orrery/adapter:evidence-bundle-to-json bundle)))
    (true (search "\"decision\":\"pass\"" json))
    (true (search "\"s1_verdict\":\"gate-pass\"" json))
    (true (search "\"drift_compatible\":true" json))
    (true (search "\"blockers\":[]" json))
    (true (search "\"artifact_shas\":[" json))))

(define-test (evidence-bundle-tests json-blocked-structure)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (bundle (%pipeline-from-target target))
         (json (orrery/adapter:evidence-bundle-to-json bundle)))
    (true (search "\"decision\":\"blocked-external\"" json))
    (true (search "\"class\":" json))
    (true (search "\"reason_code\":" json))
    (true (search "\"remediation\":" json))))

(define-test (evidence-bundle-tests json-notes-present)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :live :base-url "" :description "bad"))
         (bundle (%pipeline-from-target target))
         (json (orrery/adapter:evidence-bundle-to-json bundle)))
    (true (search "\"notes\":\"" json))
    (true (search "blocker" json))))
