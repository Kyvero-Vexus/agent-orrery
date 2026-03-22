;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-missing-artifact-normalizer-tests.lisp — tests for T1-T6 missing-artifact normalizer (wztc)

(in-package #:orrery/harness-tests)

(declaim (optimize (safety 3)))

(define-test mcp-tui-missing-artifact-normalizer-suite)

(define-test normalize-empty-scorecard-has-no-missing
  "Empty scorecard should have no missing artifacts"
  (let* ((scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p t
                     :command-match-p t
                     :command-hash 12345
                     :scenario-scores nil
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard)))
    (true (orrery/adapter:tmar-pass-p report))
    (true (= 0 (orrery/adapter:tmar-total-missing report)))))

(define-test normalize-complete-score-has-no-missing
  "Score with all artifacts present should have no missing"
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
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios nil
                     :detail "ok"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard)))
    (true (orrery/adapter:tmar-pass-p report))
    (true (= 0 (orrery/adapter:tmar-total-missing report)))))

(define-test normalize-incomplete-score-has-missing-entries
  "Score with missing artifacts should have missing entries"
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T1"
                 :screenshot-p nil
                 :transcript-p nil
                 :asciicast-p t
                 :report-p t
                 :score 2
                 :pass-p nil))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p t
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios (list "T1")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard)))
    (false (orrery/adapter:tmar-pass-p report))
    (true (= 2 (orrery/adapter:tmar-total-missing report)))))

(define-test missing-entry-has-reason-code
  "Missing artifact entry should have reason code"
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
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios (list "T1")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard)))
    (true (= 1 (length (orrery/adapter:tmar-reason-code-matrix report))))
    (let ((entry (first (orrery/adapter:tmar-reason-code-matrix report))))
      (true (eq :artifact-not-found (orrery/adapter:tmae-reason-code entry))))))

(define-test missing-entry-has-expected-path
  "Missing artifact entry should have expected path"
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T2"
                 :screenshot-p nil
                 :transcript-p t
                 :asciicast-p t
                 :report-p t
                 :score 3
                 :pass-p nil))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p t
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios (list "T2")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard)))
    (let ((entry (first (orrery/adapter:tmar-reason-code-matrix report))))
      (true (cl-ppcre:scan "artifacts/tui/T2/screenshot"
                           (orrery/adapter:tmae-expected-path entry))))))

(define-test missing-entry-has-remediation
  "Missing artifact entry should have remediation guidance"
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T3"
                 :screenshot-p nil
                 :transcript-p t
                 :asciicast-p t
                 :report-p t
                 :score 3
                 :pass-p nil))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p t
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios (list "T3")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard)))
    (let ((entry (first (orrery/adapter:tmar-reason-code-matrix report))))
      (true (cl-ppcre:scan "rerun.*T3" (orrery/adapter:tmae-remediation entry))))))

(define-test by-scenario-index-groups-correctly
  "by_scenario index should group entries by scenario"
  (let* ((score1 (orrery/adapter:make-mcp-tui-scenario-score
                  :scenario-id "T1"
                  :screenshot-p nil
                  :transcript-p t
                  :asciicast-p t
                  :report-p t
                  :score 3
                  :pass-p nil))
         (score2 (orrery/adapter:make-mcp-tui-scenario-score
                  :scenario-id "T2"
                  :screenshot-p nil
                  :transcript-p nil
                  :asciicast-p t
                  :report-p t
                  :score 2
                  :pass-p nil))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p t
                     :command-hash 12345
                     :scenario-scores (list score1 score2)
                     :missing-scenarios (list "T1" "T2")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard)))
    ;; Should have entries for both T1 and T2 in by_scenario
    (true (assoc "T1" (orrery/adapter:tmar-by-scenario report) :test #'string=))
    (true (assoc "T2" (orrery/adapter:tmar-by-scenario report) :test #'string=))))

(define-test by-kind-index-groups-correctly
  "by_kind index should group entries by artifact kind"
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T1"
                 :screenshot-p nil
                 :transcript-p nil
                 :asciicast-p t
                 :report-p t
                 :score 2
                 :pass-p nil))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p t
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios (list "T1")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard)))
    ;; Should have entries for both :screenshot and :transcript in by_kind
    (true (assoc :screenshot (orrery/adapter:tmar-by-kind report)))
    (true (assoc :transcript (orrery/adapter:tmar-by-kind report)))))

(define-test report->json-includes-reason-code-matrix
  "JSON output should include reason_code_matrix array"
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
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios (list "T1")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard))
         (json (orrery/adapter:tui-missing-artifact-report->json report)))
    (true (cl-ppcre:scan "\"reason_code_matrix\":\\[" json))
    (true (cl-ppcre:scan "\"reason\":\"artifact-not-found\"" json))))

(define-test report->json-includes-by-indices
  "JSON output should include by_scenario, by_kind, by_reason indices"
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
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios (list "T1")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard))
         (json (orrery/adapter:tui-missing-artifact-report->json report)))
    (true (cl-ppcre:scan "\"by_scenario\":\\{" json))
    (true (cl-ppcre:scan "\"by_kind\":\\{" json))
    (true (cl-ppcre:scan "\"by_reason\":\\{" json))))

(define-test report->json-includes-total-missing
  "JSON output should include total_missing count"
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T1"
                 :screenshot-p nil
                 :transcript-p nil
                 :asciicast-p t
                 :report-p t
                 :score 2
                 :pass-p nil))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p t
                     :command-hash 12345
                     :scenario-scores (list score)
                     :missing-scenarios (list "T1")
                     :detail "missing"
                     :timestamp 0))
         (report (orrery/adapter:normalize-tui-missing-artifacts scorecard))
         (json (orrery/adapter:tui-missing-artifact-report->json report)))
    (true (cl-ppcre:scan "\"total_missing\":2" json))))
