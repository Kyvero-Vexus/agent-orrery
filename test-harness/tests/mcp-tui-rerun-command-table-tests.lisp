;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-rerun-command-table-tests.lisp — tests for T1-T6 rerun command table normalizer (v8uu)

(in-package #:orrery/harness-tests)

(declaim (optimize (safety 3)))

(define-test mcp-tui-rerun-command-table-suite)

(define-test build-entry-has-correct-scenario-id
  "Entry should have the provided scenario ID"
  (let ((entry (orrery/adapter:build-tui-rerun-command-entry "T2")))
    (true (string= "T2" (orrery/adapter:trce-scenario-id entry)))))

(define-test build-entry-has-expected-command
  "Entry should have the canonical deterministic command"
  (let ((entry (orrery/adapter:build-tui-rerun-command-entry "T1")))
    (true (string= orrery/adapter:*mcp-tui-deterministic-command*
                   (orrery/adapter:trce-expected-command entry)))))

(define-test build-entry-has-expected-hash
  "Entry should have non-zero expected hash"
  (let ((entry (orrery/adapter:build-tui-rerun-command-entry "T1")))
    (true (> (orrery/adapter:trce-expected-hash entry) 0))))

(define-test build-entry-has-rerun-hint
  "Entry should have rerun hint with scenario"
  (let ((entry (orrery/adapter:build-tui-rerun-command-entry "T3")))
    (true (cl-ppcre:scan "T3" (orrery/adapter:trce-rerun-hint entry)))))

(define-test normalize-passing-scorecard-returns-pass
  "Passing scorecard should produce passing command table"
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T1"
                 :screenshot-p t
                 :transcript-p t
                 :asciicast-p t
                 :report-p t
                 :score 4
                 :pass-p t))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores (list score)
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (table (orrery/adapter:normalize-tui-rerun-command-table scorecard)))
    (true (orrery/adapter:trct-pass-p table))))

(define-test normalize-failing-scorecard-returns-fail
  "Failing scorecard should produce failing command table"
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T1"
                 :screenshot-p nil
                 :transcript-p t
                 :asciicast-p t
                 :report-p t
                 :score 3
                 :pass-p nil))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores (list score)
                     :missing-scenarios (list "T1")
                     :detail "missing"
                     :timestamp 0))
         (table (orrery/adapter:normalize-tui-rerun-command-table scorecard)))
    (false (orrery/adapter:trct-pass-p table))
    (true (= 1 (orrery/adapter:trct-missing-count table)))))

(define-test normalize-drift-scorecard-has-drift-scenarios
  "Scorecard with command drift should list drift scenarios"
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T1"
                 :screenshot-p t
                 :transcript-p t
                 :asciicast-p t
                 :report-p t
                 :score 4
                 :pass-p t))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p nil
                     :command-hash 99999 ; Wrong hash
                     :scenario-scores (list score)
                     :missing-scenarios nil
                     :detail "drift"
                     :timestamp 0))
         (table (orrery/adapter:normalize-tui-rerun-command-table scorecard)))
    (false (orrery/adapter:trct-pass-p table))
    (true (> (orrery/adapter:trct-drift-count table) 0))))

(define-test table-has-entry-per-scenario
  "Command table should have entry for each T1-T6 scenario"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (table (orrery/adapter:normalize-tui-rerun-command-table scorecard)))
    (true (= 6 (length (orrery/adapter:trct-command-table table))))))

(define-test table->json-includes-command-table-array
  "JSON output should include command_table array"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (table (orrery/adapter:normalize-tui-rerun-command-table scorecard))
         (json (orrery/adapter:tui-rerun-command-table->json table)))
    (true (cl-ppcre:scan "\"command_table\":\\[" json))))

(define-test table->json-includes-drift-missing-arrays
  "JSON output should include drift_scenarios and missing_scenarios arrays"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (table (orrery/adapter:normalize-tui-rerun-command-table scorecard))
         (json (orrery/adapter:tui-rerun-command-table->json table)))
    (true (cl-ppcre:scan "\"drift_scenarios\":\\[" json))
    (true (cl-ppcre:scan "\"missing_scenarios\":\\[" json))))

(define-test table->json-includes-deterministic-command
  "JSON output should include deterministic_command field"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (table (orrery/adapter:normalize-tui-rerun-command-table scorecard))
         (json (orrery/adapter:tui-rerun-command-table->json table)))
    (true (cl-ppcre:scan "\"deterministic_command\":" json))))

(define-test table->json-includes-counts
  "JSON output should include match_count, drift_count, missing_count"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash (orrery/adapter:command-fingerprint
                                    orrery/adapter:*mcp-tui-deterministic-command*)
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (table (orrery/adapter:normalize-tui-rerun-command-table scorecard))
         (json (orrery/adapter:tui-rerun-command-table->json table)))
    (true (cl-ppcre:scan "\"match_count\":[0-9]+" json))
    (true (cl-ppcre:scan "\"drift_count\":[0-9]+" json))
    (true (cl-ppcre:scan "\"missing_count\":[0-9]+" json))))
