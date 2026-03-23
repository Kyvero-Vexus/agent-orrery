;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-lineage-mismatch-explainer-tests.lisp — tests for T1-T6 lineage mismatch explainer (amvi)

(in-package #:orrery/harness-tests)

(declaim (optimize (safety 3)))

(define-test mcp-tui-lineage-mismatch-explainer-suite)

(define-test build-entry-no-mismatch-has-clean-class
  "Entry with no mismatch should have :no-mismatch class"
  (let ((entry (orrery/adapter:build-tui-lineage-mismatch-entry "T1" :no-mismatch)))
    (true (eq :no-mismatch (orrery/adapter:tlme-mismatch-class entry)))
    (true (null (orrery/adapter:tlme-remediation-steps entry)))))

(define-test build-entry-command-drift-has-remediation
  "Entry with command drift should have remediation steps"
  (let ((entry (orrery/adapter:build-tui-lineage-mismatch-entry "T2" :command-drift)))
    (true (eq :command-drift (orrery/adapter:tlme-mismatch-class entry)))
    (true (not (null (orrery/adapter:tlme-remediation-steps entry))))))

(define-test build-entry-artifact-missing-has-remediation
  "Entry with artifact missing should have remediation steps"
  (let ((entry (orrery/adapter:build-tui-lineage-mismatch-entry "T3" :artifact-missing)))
    (true (eq :artifact-missing (orrery/adapter:tlme-mismatch-class entry)))
    (true (not (null (orrery/adapter:tlme-remediation-steps entry))))))

(define-test build-entry-has-scenario-id
  "Entry should have the provided scenario ID"
  (let ((entry (orrery/adapter:build-tui-lineage-mismatch-entry "T5" :no-mismatch)))
    (true (string= "T5" (orrery/adapter:tlme-scenario-id entry)))))

(define-test remediation-step-has-fields
  "Remediation step should have step-id, description, and command"
  (let* ((entry (orrery/adapter:build-tui-lineage-mismatch-entry "T4" :command-drift))
         (step (first (orrery/adapter:tlme-remediation-steps entry))))
    (true (stringp (orrery/adapter:tlrs-step-id step)))
    (true (stringp (orrery/adapter:tlrs-description step)))
    (true (stringp (orrery/adapter:tlrs-command step)))))

(define-test report-struct-has-required-fields
  "Report struct should have all required fields"
  (let ((report (orrery/adapter:make-tui-lineage-mismatch-report
                 :pass-p t
                 :clean-count 6
                 :mismatch-count 0
                 :mismatch-matrix nil
                 :by-mismatch-class nil
                 :remediation-matrix nil
                 :command-hash 12345
                 :detail "ok"
                 :timestamp 0)))
    (true (orrery/adapter:tlmr-pass-p report))
    (true (= 6 (orrery/adapter:tlmr-clean-count report)))
    (true (= 0 (orrery/adapter:tlmr-mismatch-count report)))))

(define-test report->json-includes-pass-field
  "JSON output should include pass field"
  (let* ((report (orrery/adapter:make-tui-lineage-mismatch-report
                  :pass-p t
                  :clean-count 6
                  :mismatch-count 0
                  :mismatch-matrix nil
                  :by-mismatch-class nil
                  :remediation-matrix nil
                  :command-hash 12345
                  :detail "ok"
                  :timestamp 0))
         (json (orrery/adapter:tui-lineage-mismatch-report->json report)))
    (true (cl-ppcre:scan "\"pass\":true" json))))

(define-test report->json-includes-counts
  "JSON output should include clean_count and mismatch_count"
  (let* ((report (orrery/adapter:make-tui-lineage-mismatch-report
                  :pass-p t
                  :clean-count 6
                  :mismatch-count 0
                  :mismatch-matrix nil
                  :by-mismatch-class nil
                  :remediation-matrix nil
                  :command-hash 12345
                  :detail "ok"
                  :timestamp 0))
         (json (orrery/adapter:tui-lineage-mismatch-report->json report)))
    (true (cl-ppcre:scan "\"clean_count\":6" json))
    (true (cl-ppcre:scan "\"mismatch_count\":0" json))))

(define-test report->json-includes-mismatch-matrix
  "JSON output should include mismatch_matrix array"
  (let* ((report (orrery/adapter:make-tui-lineage-mismatch-report
                  :pass-p t
                  :clean-count 6
                  :mismatch-count 0
                  :mismatch-matrix nil
                  :by-mismatch-class nil
                  :remediation-matrix nil
                  :command-hash 12345
                  :detail "ok"
                  :timestamp 0))
         (json (orrery/adapter:tui-lineage-mismatch-report->json report)))
    (true (cl-ppcre:scan "\"mismatch_matrix\":\\[" json))))

(define-test report->json-includes-remediation-matrix
  "JSON output should include remediation_matrix object"
  (let* ((report (orrery/adapter:make-tui-lineage-mismatch-report
                  :pass-p t
                  :clean-count 6
                  :mismatch-count 0
                  :mismatch-matrix nil
                  :by-mismatch-class nil
                  :remediation-matrix nil
                  :command-hash 12345
                  :detail "ok"
                  :timestamp 0))
         (json (orrery/adapter:tui-lineage-mismatch-report->json report)))
    (true (cl-ppcre:scan "\"remediation_matrix\":\\{" json))))
