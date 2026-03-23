;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic4-closure-attestation-exporter-tests.lisp — tests for S1-S6 closure attestation exporter
;;; Bead: agent-orrery-nlup

(in-package #:orrery/harness-tests)

(define-test epic4-closure-attestation-exporter)

(define-test (epic4-closure-attestation-exporter replay-row->attestation-converts-basic-row)
  (let* ((row (orrery/adapter:make-playwright-replay-row
               :scenario-id "S1"
               :command "cd e2e && bash run-e2e.sh"
               :command-hash 12345
               :screenshot-path "/tmp/s1.png"
               :trace-path "/tmp/s1.zip"
               :transcript-hash 999
               :preflight-ok-p t
               :failure-codes nil))
         (att (orrery/adapter:replay-row->attestation row)))
    (is equal "S1" (orrery/adapter:e4sa-scenario-id att))
    (is = 12345 (orrery/adapter:e4sa-command-fingerprint att))
    (true (orrery/adapter:e4sa-screenshot-present-p att))
    (true (orrery/adapter:e4sa-trace-present-p att))
    (is eq :pass (orrery/adapter:e4sa-verdict att))))

(define-test (epic4-closure-attestation-exporter attestation-missing-artifacts-has-fail-verdict)
  (let* ((row (orrery/adapter:make-playwright-replay-row
               :scenario-id "S2"
               :command "cd e2e && bash run-e2e.sh"
               :command-hash 12345
               :screenshot-path ""
               :trace-path ""
               :transcript-hash 0
               :preflight-ok-p nil
               :failure-codes '("E4_MISSING_SCR")))
         (att (orrery/adapter:replay-row->attestation row)))
    (false (orrery/adapter:e4sa-screenshot-present-p att))
    (false (orrery/adapter:e4sa-trace-present-p att))
    (is eq :fail (orrery/adapter:e4sa-verdict att))))

(define-test (epic4-closure-attestation-exporter compile-closed-when-complete)
  (let* ((rows (loop for i from 1 to 6
                     collect (orrery/adapter:make-playwright-replay-row
                              :scenario-id (format nil "S~D" i)
                              :command "cd e2e && bash run-e2e.sh"
                              :command-hash orrery/adapter:*playwright-canonical-command-hash*
                              :screenshot-path (format nil "/tmp/s~D.png" i)
                              :trace-path (format nil "/tmp/s~D.zip" i)
                              :transcript-hash i
                              :preflight-ok-p t
                              :failure-codes nil)))
         (table (orrery/adapter:make-playwright-replay-table
                 :run-id "test-run"
                 :command orrery/adapter:*playwright-canonical-command*
                 :command-hash orrery/adapter:*playwright-canonical-command-hash*
                 :rows rows
                 :pass-p t
                 :fail-count 0
                 :timestamp 0))
         (merger (orrery/adapter:make-pw-attestation-merger-report
                  :pass-p t
                  :command-match-p t
                  :rows nil
                  :missing-scenarios nil
                  :drift-scenarios nil
                  :command-hash 12345
                  :expected-hash 12345
                  :detail "ok"
                  :timestamp 0))
         (att (orrery/adapter:compile-epic4-closure-attestation table merger)))
    (is eq :closed (orrery/adapter:e4ca-closure-verdict att))
    (is = 1.0 (orrery/adapter:e4ca-scenario-coverage att))))

(define-test (epic4-closure-attestation-exporter compile-open-when-incomplete)
  (let* ((rows (list (orrery/adapter:make-playwright-replay-row
                      :scenario-id "S1"
                      :command orrery/adapter:*playwright-canonical-command*
                      :command-hash orrery/adapter:*playwright-canonical-command-hash*
                      :screenshot-path ""
                      :trace-path ""
                      :transcript-hash 0
                      :preflight-ok-p nil
                      :failure-codes '("MISSING"))))
         (table (orrery/adapter:make-playwright-replay-table
                 :run-id "test-run"
                 :command orrery/adapter:*playwright-canonical-command*
                 :command-hash orrery/adapter:*playwright-canonical-command-hash*
                 :rows rows
                 :pass-p nil
                 :fail-count 1
                 :timestamp 0))
         (merger (orrery/adapter:make-pw-attestation-merger-report
                  :pass-p nil
                  :command-match-p t
                  :rows nil
                  :missing-scenarios (list "S2" "S3" "S4" "S5" "S6")
                  :drift-scenarios nil
                  :command-hash 12345
                  :expected-hash 12345
                  :detail "incomplete"
                  :timestamp 0))
         (att (orrery/adapter:compile-epic4-closure-attestation table merger)))
    (is eq :open (orrery/adapter:e4ca-closure-verdict att))))

(define-test (epic4-closure-attestation-exporter json-serialization-deterministic)
  (let* ((row (orrery/adapter:make-playwright-replay-row
               :scenario-id "S1"
               :command "test"
               :command-hash 1
               :screenshot-path "/tmp/s1.png"
               :trace-path "/tmp/s1.zip"
               :transcript-hash 1
               :preflight-ok-p t
               :failure-codes nil))
         (table (orrery/adapter:make-playwright-replay-table
                 :run-id "test"
                 :command "test"
                 :command-hash 1
                 :rows (list row)
                 :pass-p t
                 :fail-count 0
                 :timestamp 12345))
         (merger (orrery/adapter:make-pw-attestation-merger-report
                  :pass-p t
                  :command-match-p t
                  :rows nil
                  :missing-scenarios nil
                  :drift-scenarios nil
                  :command-hash 1
                  :expected-hash 1
                  :detail "ok"
                  :timestamp 12345))
         (att (orrery/adapter:compile-epic4-closure-attestation table merger))
         (json1 (orrery/adapter:epic4-closure-attestation->json att))
         (json2 (orrery/adapter:epic4-closure-attestation->json att)))
    (is equal json1 json2)))
