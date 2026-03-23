;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic4-closure-attestation-exporter-tests.lisp — tests for S1-S6 attestation exporter
;;; Bead: agent-orrery-xx9m

(in-package #:orrery/harness-tests)

(define-test "epic4-closure-attestation-exporter" 
  (let ((suite (make-instance 'test-suite :name "epic4-closure-attestation-exporter")))
    
    ;; Test 1: replay-row->attestation converts basic row
    (add-test suite
              (make-instance 'test-case
                :name "replay-row->attestation converts basic row"
                :run-fn (lambda ()
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
                            (assert-equal "S1" (orrery/adapter:e4sa-scenario-id att))
                            (assert-equal 12345 (orrery/adapter:e4sa-command-fingerprint att))
                            (assert-true (orrery/adapter:e4sa-screenshot-present-p att))
                            (assert-true (orrery/adapter:e4sa-trace-present-p att))
                            (assert-equal :pass (orrery/adapter:e4sa-verdict att))))))
    
    ;; Test 2: attestation missing artifacts has fail verdict
    (add-test suite
              (make-instance 'test-case
                :name "attestation missing artifacts has fail verdict"
                :run-fn (lambda ()
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
                            (assert-false (orrery/adapter:e4sa-screenshot-present-p att))
                            (assert-false (orrery/adapter:e4sa-trace-present-p att))
                            (assert-equal :fail (orrery/adapter:e4sa-verdict att))))))
    
    ;; Test 3: compile-epic4-closure-attestation produces closed verdict when complete
    (add-test suite
              (make-instance 'test-case
                :name "compile-epic4-closure-attestation closed when complete"
                :run-fn (lambda ()
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
                                          :artifact-complete-p t
                                          :findings nil))
                                 (att (orrery/adapter:compile-epic4-closure-attestation table merger)))
                            (assert-equal :closed (orrery/adapter:e4ca-closure-verdict att))
                            (assert-equal 1.0 (orrery/adapter:e4ca-scenario-coverage att))))))
    
    ;; Test 4: compile-epic4-closure-attestation open when incomplete
    (add-test suite
              (make-instance 'test-case
                :name "compile-epic4-closure-attestation open when incomplete"
                :run-fn (lambda ()
                          (let* ((rows (list (orrery/adapter:make-playwright-replay-row
                                              :scenario-id "S1"
                                              :command orrery/adapter:*playwright-canonical-command*
                                              :command-hash orrery/adapter:*playwright-canonical-command-hash*
                                              :screenshot-path ""
                                              :trace-path ""
                                              :transcript-hash 0
                                              :preflight-ok-p nil
                                              :failure-codes '("MISSING")))))
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
                                          :artifact-complete-p nil
                                          :findings nil))
                                 (att (orrery/adapter:compile-epic4-closure-attestation table merger)))
                            (assert-equal :open (orrery/adapter:e4ca-closure-verdict att)))))
    
    ;; Test 5: JSON serialization is deterministic
    (add-test suite
              (make-instance 'test-case
                :name "JSON serialization is deterministic"
                :run-fn (lambda ()
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
                                          :artifact-complete-p t
                                          :findings nil))
                                 (att (orrery/adapter:compile-epic4-closure-attestation table merger))
                                 (json1 (orrery/adapter:epic4-closure-attestation->json att))
                                 (json2 (orrery/adapter:epic4-closure-attestation->json att)))
                            (assert-equal json1 json2)))))
    
    suite))
