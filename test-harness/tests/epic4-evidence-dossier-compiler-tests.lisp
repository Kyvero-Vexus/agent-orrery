;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic4-evidence-dossier-compiler-tests.lisp — tests for S1-S6 evidence dossier compiler
;;; Bead: agent-orrery-nlup

(in-package #:orrery/test-harness)

(define-test "epic4-evidence-dossier-compiler" 
  (let ((suite (make-instance 'test-suite :name "epic4-evidence-dossier-compiler")))
    
    ;; Test 1: attestation->scenario-record converts basic attestation
    (add-test suite
              (make-instance 'test-case
                :name "attestation->scenario-record converts basic attestation"
                :run-fn (lambda ()
                          (let* ((att (orrery/adapter:make-epic4-scenario-attestation
                                       :scenario-id "S1"
                                       :command-fingerprint 12345
                                       :screenshot-present-p t
                                       :screenshot-path "/tmp/s1.png"
                                       :screenshot-digest "ABC123"
                                       :trace-present-p t
                                       :trace-path "/tmp/s1.zip"
                                       :trace-digest "DEF456"
                                       :transcript-fingerprint 999
                                       :verdict :pass))
                                 (rec (orrery/adapter:attestation->scenario-record att)))
                            (assert-equal "S1" (orrery/adapter:e4sr-scenario-id rec))
                            (assert-equal 12345 (orrery/adapter:e4sr-command-fingerprint rec))
                            (assert-true (orrery/adapter:e4sr-evidence-complete-p rec))
                            (assert-equal :pass (orrery/adapter:e4sr-verdict rec))))))
    
    ;; Test 2: scenario record marks incomplete when missing artifacts
    (add-test suite
              (make-instance 'test-case
                :name "scenario record incomplete when missing artifacts"
                :run-fn (lambda ()
                          (let* ((att (orrery/adapter:make-epic4-scenario-attestation
                                       :scenario-id "S2"
                                       :command-fingerprint 12345
                                       :screenshot-present-p nil
                                       :screenshot-path ""
                                       :screenshot-digest ""
                                       :trace-present-p nil
                                       :trace-path ""
                                       :trace-digest ""
                                       :transcript-fingerprint 0
                                       :verdict :fail))
                                 (rec (orrery/adapter:attestation->scenario-record att)))
                            (assert-false (orrery/adapter:e4sr-evidence-complete-p rec))
                            (assert-equal :missing (orrery/adapter:e4sr-verdict rec))))))
    
    ;; Test 3: build-scenario-diagnostic creates pass diagnostic when complete
    (add-test suite
              (make-instance 'test-case
                :name "build-scenario-diagnostic pass when complete"
                :run-fn (lambda ()
                          (let* ((att (orrery/adapter:make-epic4-scenario-attestation
                                       :scenario-id "S1"
                                       :command-fingerprint orrery/adapter:*playwright-canonical-command-hash*
                                       :screenshot-present-p t
                                       :screenshot-path "/tmp/s1.png"
                                       :screenshot-digest "ABC123"
                                       :trace-present-p t
                                       :trace-path "/tmp/s1.zip"
                                       :trace-digest "DEF456"
                                       :transcript-fingerprint 999
                                       :verdict :pass))
                                 (rec (orrery/adapter:attestation->scenario-record att))
                                 (diag (orrery/adapter:build-scenario-diagnostic att rec)))
                            (assert-equal "S1" (orrery/adapter:edd-scenario-id diag))
                            (assert-equal :pass (orrery/adapter:edd-category diag))))))
    
    ;; Test 4: build-scenario-diagnostic creates missing-screenshot diagnostic
    (add-test suite
              (make-instance 'test-case
                :name "build-scenario-diagnostic missing-screenshot"
                :run-fn (lambda ()
                          (let* ((att (orrery/adapter:make-epic4-scenario-attestation
                                       :scenario-id "S2"
                                       :command-fingerprint orrery/adapter:*playwright-canonical-command-hash*
                                       :screenshot-present-p nil
                                       :screenshot-path ""
                                       :screenshot-digest ""
                                       :trace-present-p t
                                       :trace-path "/tmp/s2.zip"
                                       :trace-digest "DEF456"
                                       :transcript-fingerprint 999
                                       :verdict :fail))
                                 (rec (orrery/adapter:attestation->scenario-record att))
                                 (diag (orrery/adapter:build-scenario-diagnostic att rec)))
                            (assert-equal :missing-screenshot (orrery/adapter:edd-category diag))))))
    
    ;; Test 5: compile-epic4-evidence-dossier produces closed verdict when complete
    (add-test suite
              (make-instance 'test-case
                :name "compile-epic4-evidence-dossier closed when complete"
                :run-fn (lambda ()
                          (let* ((atts (loop for i from 1 to 6
                                             collect (orrery/adapter:make-epic4-scenario-attestation
                                                      :scenario-id (format nil "S~D" i)
                                                      :command-fingerprint orrery/adapter:*playwright-canonical-command-hash*
                                                      :screenshot-present-p t
                                                      :screenshot-path (format nil "/tmp/s~D.png" i)
                                                      :screenshot-digest (format nil "SCR~D" i)
                                                      :trace-present-p t
                                                      :trace-path (format nil "/tmp/s~D.zip" i)
                                                      :trace-digest (format nil "TRC~D" i)
                                                      :transcript-fingerprint i
                                                      :verdict :pass)))
                                 (att (orrery/adapter:make-epic4-closure-attestation
                                       :run-id "test-run"
                                       :lineage-tag "eb0.4.5"
                                       :deterministic-command orrery/adapter:*playwright-canonical-command*
                                       :command-fingerprint orrery/adapter:*playwright-canonical-command-hash*
                                       :scenario-coverage 1.0
                                       :attestations atts
                                       :screenshot-digests nil
                                       :trace-digests nil
                                       :transcript-fingerprints nil
                                       :fail-closed-diagnostics nil
                                       :closure-verdict :closed
                                       :timestamp 0
                                       :policy-note "test"))
                                 (dossier (orrery/adapter:compile-epic4-evidence-dossier att)))
                            (assert-equal :closed (orrery/adapter:e4ed-closure-verdict dossier))
                            (assert-equal 1.0 (orrery/adapter:e4ed-scenario-coverage dossier))
                            (assert-equal 6 (length (orrery/adapter:e4ed-records dossier)))))))
    
    ;; Test 6: compile-epic4-evidence-dossier open when incomplete
    (add-test suite
              (make-instance 'test-case
                :name "compile-epic4-evidence-dossier open when incomplete"
                :run-fn (lambda ()
                          (let* ((atts (list (orrery/adapter:make-epic4-scenario-attestation
                                              :scenario-id "S1"
                                              :command-fingerprint orrery/adapter:*playwright-canonical-command-hash*
                                              :screenshot-present-p nil
                                              :screenshot-path ""
                                              :screenshot-digest ""
                                              :trace-present-p nil
                                              :trace-path ""
                                              :trace-digest ""
                                              :transcript-fingerprint 0
                                              :verdict :fail)))
                                 (att (orrery/adapter:make-epic4-closure-attestation
                                       :run-id "test-run"
                                       :lineage-tag "eb0.4.5"
                                       :deterministic-command orrery/adapter:*playwright-canonical-command*
                                       :command-fingerprint orrery/adapter:*playwright-canonical-command-hash*
                                       :scenario-coverage 0.0
                                       :attestations atts
                                       :screenshot-digests nil
                                       :trace-digests nil
                                       :transcript-fingerprints nil
                                       :fail-closed-diagnostics nil
                                       :closure-verdict :open
                                       :timestamp 0
                                       :policy-note "test"))
                                 (dossier (orrery/adapter:compile-epic4-evidence-dossier att)))
                            (assert-equal :open (orrery/adapter:e4ed-closure-verdict dossier)))))
    
    ;; Test 7: JSON serialization is deterministic
    (add-test suite
              (make-instance 'test-case
                :name "JSON serialization is deterministic"
                :run-fn (lambda ()
                          (let* ((att (orrery/adapter:make-epic4-scenario-attestation
                                       :scenario-id "S1"
                                       :command-fingerprint 1
                                       :screenshot-present-p t
                                       :screenshot-path "/tmp/s1.png"
                                       :screenshot-digest "ABC"
                                       :trace-present-p t
                                       :trace-path "/tmp/s1.zip"
                                       :trace-digest "DEF"
                                       :transcript-fingerprint 1
                                       :verdict :pass))
                                 (closure-att (orrery/adapter:make-epic4-closure-attestation
                                               :run-id "test"
                                               :lineage-tag "eb0.4.5"
                                               :deterministic-command "test"
                                               :command-fingerprint 1
                                               :scenario-coverage 1.0
                                               :attestations (list att)
                                               :screenshot-digests nil
                                               :trace-digests nil
                                               :transcript-fingerprints nil
                                               :fail-closed-diagnostics nil
                                               :closure-verdict :closed
                                               :timestamp 12345
                                               :policy-note "test"))
                                 (dossier (orrery/adapter:compile-epic4-evidence-dossier closure-att))
                                 (json1 (orrery/adapter:epic4-evidence-dossier->json dossier))
                                 (json2 (orrery/adapter:epic4-evidence-dossier->json dossier)))
                            (assert-equal json1 json2)))))
    
    suite))
