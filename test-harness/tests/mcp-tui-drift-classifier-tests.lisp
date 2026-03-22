;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-drift-classifier-tests.lisp — tests for T1-T6 command-hash drift classifier (l7ni)

(in-package #:orrery/harness-tests)

(declaim (optimize (safety 3)))

(define-test mcp-tui-drift-classifier-suite)

(define-test classify-no-drift-when-hashes-match
  "Should classify as :no-drift when expected and actual hashes match"
  (let* ((hash 12345)
         (hint (orrery/adapter:classify-tui-scenario-drift "T1" hash hash)))
    (true (eq :no-drift (orrery/adapter:tdh-drift-class hint)))
    (true (string= "T1" (orrery/adapter:tdh-scenario-id hint)))
    (true (= hash (orrery/adapter:tdh-expected-hash hint)))
    (true (= hash (orrery/adapter:tdh-actual-hash hint)))
    (true (string= "" (orrery/adapter:tdh-remediation hint)))))

(define-test classify-command-mismatch-when-hashes-differ
  "Should classify as :command-mismatch when hashes differ"
  (let ((hint (orrery/adapter:classify-tui-scenario-drift "T2" 11111 22222)))
    (true (eq :command-mismatch (orrery/adapter:tdh-drift-class hint)))
    (true (string= "T2" (orrery/adapter:tdh-scenario-id hint)))
    (true (= 11111 (orrery/adapter:tdh-expected-hash hint)))
    (true (= 22222 (orrery/adapter:tdh-actual-hash hint)))
    (true (cl-ppcre:scan "rerun.*T2" (orrery/adapter:tdh-remediation hint)))))

(define-test classify-lineage-unknown-when-expected-hash-is-zero
  "Should classify as :lineage-unknown when expected hash is 0"
  (let ((hint (orrery/adapter:classify-tui-scenario-drift "T3" 0 12345)))
    (true (eq :lineage-unknown (orrery/adapter:tdh-drift-class hint)))))

(define-test classify-lineage-unknown-when-actual-hash-is-zero
  "Should classify as :lineage-unknown when actual hash is 0"
  (let ((hint (orrery/adapter:classify-tui-scenario-drift "T4" 12345 0)))
    (true (eq :lineage-unknown (orrery/adapter:tdh-drift-class hint)))))

(define-test classify-tui-command-hash-drift-creates-per-scenario-hints
  "Should create drift hints for all T1-T6 scenarios"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (classification (orrery/adapter:classify-tui-command-hash-drift scorecard)))
    (true (= 6 (length (orrery/adapter:tdc-drift-classes classification))))
    (true (every (lambda (hint) (find (orrery/adapter:tdh-scenario-id hint)
                                      '("T1" "T2" "T3" "T4" "T5" "T6")
                                      :test #'string=))
                 (orrery/adapter:tdc-drift-classes classification)))))

(define-test classify-tui-command-hash-drift-counts-stable-vs-drift
  "Should correctly count stable vs drift scenarios"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (classification (orrery/adapter:classify-tui-command-hash-drift scorecard)))
    (true (= 6 (orrery/adapter:tdc-stable-count classification)))
    (true (= 0 (orrery/adapter:tdc-drift-count classification)))))

(define-test classify-tui-command-hash-drift-passes-when-all-stable
  "Should pass when all scenarios have no drift"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (classification (orrery/adapter:classify-tui-command-hash-drift scorecard)))
    (true (orrery/adapter:tdc-pass-p classification))))

(define-test classify-tui-command-hash-drift-includes-remediation-hints
  "Should include remediation hints for drift scenarios"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p nil
                     :command-hash 99999 ; Mismatch hash
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "drift"
                     :timestamp 0))
         (classification (orrery/adapter:classify-tui-command-hash-drift scorecard)))
    ;; 6 drift scenarios should produce 6 remediation hints
    (true (= 6 (length (orrery/adapter:tdc-remediation-hints classification))))))

(define-test drift-classification->json-includes-drift-classes-array
  "JSON output should include drift_classes array"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (classification (orrery/adapter:classify-tui-command-hash-drift scorecard))
         (json (orrery/adapter:tui-drift-classification->json classification)))
    (true (cl-ppcre:scan "\"drift_classes\":\\[" json))
    (true (cl-ppcre:scan "\"drift_class\":\"no-drift\"" json))))

(define-test drift-classification->json-includes-remediation-hints-array
  "JSON output should include remediation_hints array"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (classification (orrery/adapter:classify-tui-command-hash-drift scorecard))
         (json (orrery/adapter:tui-drift-classification->json classification)))
    (true (cl-ppcre:scan "\"remediation_hints\":\\[" json))))

(define-test drift-classification->json-includes-counts
  "JSON output should include drift_count and stable_count"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (classification (orrery/adapter:classify-tui-command-hash-drift scorecard))
         (json (orrery/adapter:tui-drift-classification->json classification)))
    (true (cl-ppcre:scan "\"drift_count\":0" json))
    (true (cl-ppcre:scan "\"stable_count\":6" json))))

(define-test drift-classification->json-includes-command-hashes
  "JSON output should include command_hash and expected_hash"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (classification (orrery/adapter:classify-tui-command-hash-drift scorecard))
         (json (orrery/adapter:tui-drift-classification->json classification)))
    (true (cl-ppcre:scan "\"command_hash\":[0-9]+" json))
    (true (cl-ppcre:scan "\"expected_hash\":[0-9]+" json))))
