;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic4-evidence-dossier-compiler-tests.lisp — tests for S1-S6 evidence dossier compiler
;;; Bead: agent-orrery-nlup

(in-package #:orrery/harness-tests)

(define-test epic4-evidence-dossier-compiler)

(define-test (epic4-evidence-dossier-compiler attestation->scenario-record-converts-basic)
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
    (is equal "S1" (orrery/adapter:e4sr-scenario-id rec))
    (is = 12345 (orrery/adapter:e4sr-command-fingerprint rec))
    (true (orrery/adapter:e4sr-evidence-complete-p rec))
    (is eq :pass (orrery/adapter:e4sr-verdict rec))))

(define-test (epic4-evidence-dossier-compiler scenario-record-incomplete-when-missing-artifacts)
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
    (false (orrery/adapter:e4sr-evidence-complete-p rec))
    (is eq :missing (orrery/adapter:e4sr-verdict rec))))

(define-test (epic4-evidence-dossier-compiler build-scenario-diagnostic-pass-when-complete)
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
    (is equal "S1" (orrery/adapter:edd-scenario-id diag))
    (is eq :pass (orrery/adapter:edd-category diag))))

(define-test (epic4-evidence-dossier-compiler build-scenario-diagnostic-missing-screenshot)
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
    (is eq :missing-screenshot (orrery/adapter:edd-category diag))))

(define-test (epic4-evidence-dossier-compiler compile-closed-when-complete)
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
    (is eq :closed (orrery/adapter:e4ed-closure-verdict dossier))
    (is = 1.0 (orrery/adapter:e4ed-scenario-coverage dossier))
    (is = 6 (length (orrery/adapter:e4ed-records dossier)))))

(define-test (epic4-evidence-dossier-compiler compile-open-when-incomplete)
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
    (is eq :open (orrery/adapter:e4ed-closure-verdict dossier))))

(define-test (epic4-evidence-dossier-compiler json-serialization-deterministic)
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
    (is equal json1 json2)))
