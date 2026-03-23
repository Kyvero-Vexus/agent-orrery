;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; unified-closure-gate.lisp — typed Epic 3/4 unified closure gate
;;; Bead: agent-orrery-2wb
;;;
;;; Consumes dual-framework closure certificate and performs artifact-manifest
;;; integrity checks and deterministic command reference validation. Emits a
;;; single machine-checkable readiness verdict for release reporting.
;;; Fail-closed: prohibits Epic 3 or Epic 4 complete reporting when evidence
;;; is incomplete.

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype gate-readiness-verdict ()
  '(member :ready :not-ready :partial))

(deftype integrity-check-status ()
  '(member :intact :corrupted :missing :drift-detected))

;;; ── Integrity Check Structures ───────────────────────────────────────────────

(defstruct (manifest-integrity-check (:conc-name mic-))
  "Artifact manifest integrity check result."
  (framework :unknown :type (member :epic3 :epic4 :both))
  (artifacts-checked 0 :type integer)
  (artifacts-intact 0 :type integer)
  (artifacts-missing 0 :type integer)
  (artifacts-drifted 0 :type integer)
  (status :intact :type integrity-check-status)
  (details nil :type list))

(defstruct (command-reference-check (:conc-name crc-))
  "Deterministic command reference validation result."
  (framework :unknown :type (member :epic3 :epic4 :both))
  (command-canonical-p nil :type boolean)
  (fingerprint-matches-p nil :type boolean)
  (expected-command "" :type string)
  (actual-fingerprint 0 :type integer)
  (status :intact :type integrity-check-status)
  (detail "" :type string))

;;; ── Unified Gate Verdict ─────────────────────────────────────────────────────

(defstruct (unified-closure-gate-verdict (:conc-name ucgv-))
  "Machine-checkable readiness verdict for release gates."
  ;; Identity
  (gate-id "" :type string)
  (certificate-run-id "" :type string)
  (gate-version 1 :type integer)
  
  ;; Overall verdict
  (readiness-verdict :not-ready :type gate-readiness-verdict)
  (gate-outcome :blocked :type (member :pass :blocked :escalate))
  
  ;; Framework-specific checks
  (epic3-manifest-check nil :type (or null manifest-integrity-check))
  (epic4-manifest-check nil :type (or null manifest-integrity-check))
  (epic3-command-check nil :type (or null command-reference-check))
  (epic4-command-check nil :type (or null command-reference-check))
  
  ;; Evidence summary
  (total-artifacts 0 :type integer)
  (intact-artifacts 0 :type integer)
  (epic3-pass-p nil :type boolean)
  (epic4-pass-p nil :type boolean)
  
  ;; Blocking issues
  (blockers nil :type list)
  (remediation-actions nil :type list)
  
  ;; Timestamps
  (certificate-timestamp 0 :type integer)
  (gate-timestamp 0 :type integer)
  
  ;; Policy enforcement
  (policy-note "Epic 3 and Epic 4 evidence MUST be complete and verified for release readiness." :type string))

;;; ── Declaims ─────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (dual-framework-certificate) (values manifest-integrity-check &optional))
        verify-epic3-manifest-integrity)
 (ftype (function (dual-framework-certificate) (values manifest-integrity-check &optional))
        verify-epic4-manifest-integrity)
 (ftype (function (dual-framework-certificate) (values command-reference-check &optional))
        verify-epic3-command-reference)
 (ftype (function (dual-framework-certificate) (values command-reference-check &optional))
        verify-epic4-command-reference)
 (ftype (function (dual-framework-certificate) (values unified-closure-gate-verdict &optional))
        evaluate-unified-closure-gate)
 (ftype (function (unified-closure-gate-verdict) (values string &optional))
        unified-closure-gate-verdict->json))

;;; ── Manifest Integrity Verification ──────────────────────────────────────────

(defun verify-epic3-manifest-integrity (certificate)
  "Verify Epic 3 artifact manifest integrity from certificate."
  (declare (type dual-framework-certificate certificate)
           (optimize (safety 3)))
  (let* ((proof (dfc-epic3-evidence-proof certificate))
         (rollup (dfc-artifact-rollup certificate))
         (epic3-artifacts (remove-if-not (lambda (e) (eq (are-framework e) :epic3)) rollup))
         (checked (length epic3-artifacts))
         (intact (count-if (lambda (e) (> (length (are-digest e)) 0)) epic3-artifacts))
         (missing (- checked intact))
         (status (cond
                   ((null proof) :missing)
                   ((= checked 0) :missing)
                   ((= missing 0) :intact)
                   ((< missing checked) :drift-detected)
                   (t :corrupted))))
    (make-manifest-integrity-check
     :framework :epic3
     :artifacts-checked checked
     :artifacts-intact intact
     :artifacts-missing missing
     :artifacts-drifted 0
     :status status
     :details (when (> missing 0)
                (list (format nil "~D/~D artifacts missing digests" missing checked))))))

(defun verify-epic4-manifest-integrity (certificate)
  "Verify Epic 4 artifact manifest integrity from certificate."
  (declare (type dual-framework-certificate certificate)
           (optimize (safety 3)))
  (let* ((proof (dfc-epic4-evidence-proof certificate))
         (rollup (dfc-artifact-rollup certificate))
         (epic4-artifacts (remove-if-not (lambda (e) (eq (are-framework e) :epic4)) rollup))
         (checked (length epic4-artifacts))
         (intact (count-if (lambda (e) (> (length (are-digest e)) 0)) epic4-artifacts))
         (missing (- checked intact))
         (status (cond
                   ((null proof) :missing)
                   ((= checked 0) :missing)
                   ((= missing 0) :intact)
                   ((< missing checked) :drift-detected)
                   (t :corrupted))))
    (make-manifest-integrity-check
     :framework :epic4
     :artifacts-checked checked
     :artifacts-intact intact
     :artifacts-missing missing
     :artifacts-drifted 0
     :status status
     :details (when (> missing 0)
                (list (format nil "~D/~D artifacts missing digests" missing checked))))))

;;; ── Command Reference Validation ─────────────────────────────────────────────

(defun verify-epic3-command-reference (certificate)
  "Verify Epic 3 deterministic command reference from certificate."
  (declare (type dual-framework-certificate certificate)
           (optimize (safety 3)))
  (let* ((proof (dfc-epic3-evidence-proof certificate))
         (fp (dfc-epic3-command-fingerprint certificate))
         (canonical-p (and proof (e3ep-artifacts-present-p proof)))
         (matches-p (and proof (plusp fp)))
         (status (cond
                   ((null proof) :missing)
                   ((and canonical-p matches-p) :intact)
                   ((not canonical-p) :drift-detected)
                   (t :corrupted))))
    (make-command-reference-check
     :framework :epic3
     :command-canonical-p canonical-p
     :fingerprint-matches-p matches-p
     :expected-command *tui-deterministic-command*
     :actual-fingerprint fp
     :status status
     :detail (if (null proof)
                 "Epic 3 evidence proof missing"
                 (format nil "Fingerprint: ~D, Canonical: ~A" fp canonical-p)))))

(defun verify-epic4-command-reference (certificate)
  "Verify Epic 4 deterministic command reference from certificate."
  (declare (type dual-framework-certificate certificate)
           (optimize (safety 3)))
  (let* ((proof (dfc-epic4-evidence-proof certificate))
         (fp (dfc-epic4-command-fingerprint certificate))
         (canonical-p (and proof (e4ep-screenshots-present-p proof) (e4ep-traces-present-p proof)))
         (matches-p (and proof (plusp fp)))
         (status (cond
                   ((null proof) :missing)
                   ((and canonical-p matches-p) :intact)
                   ((not canonical-p) :drift-detected)
                   (t :corrupted))))
    (make-command-reference-check
     :framework :epic4
     :command-canonical-p canonical-p
     :fingerprint-matches-p matches-p
     :expected-command *playwright-canonical-command*
     :actual-fingerprint fp
     :status status
     :detail (if (null proof)
                 "Epic 4 evidence proof missing"
                 (format nil "Fingerprint: ~D, Canonical: ~A" fp canonical-p)))))

;;; ── Blocker Detection ────────────────────────────────────────────────────────

(defun %detect-blockers (epic3-manifest epic4-manifest epic3-cmd epic4-cmd fps-match)
  "Detect blocking issues from integrity checks."
  (declare (type (or null manifest-integrity-check) epic3-manifest epic4-manifest)
           (type (or null command-reference-check) epic3-cmd epic4-cmd)
           (type boolean fps-match))
  (let ((blockers nil))
    ;; Epic 3 manifest issues
    (when (and epic3-manifest (not (eq (mic-status epic3-manifest) :intact)))
      (push (format nil "epic3-manifest-~A" (mic-status epic3-manifest)) blockers))
    (when (and epic4-manifest (not (eq (mic-status epic4-manifest) :intact)))
      (push (format nil "epic4-manifest-~A" (mic-status epic4-manifest)) blockers))
    (when (and epic3-cmd (not (eq (crc-status epic3-cmd) :intact)))
      (push (format nil "epic3-command-~A" (crc-status epic3-cmd)) blockers))
    (when (and epic4-cmd (not (eq (crc-status epic4-cmd) :intact)))
      (push (format nil "epic4-command-~A" (crc-status epic4-cmd)) blockers))
    (when (not fps-match)
      (push "command-fingerprints-mismatch" blockers))
    ;; Missing proofs
    (unless epic3-manifest
      (push "epic3-evidence-proof-missing" blockers))
    (unless epic4-manifest
      (push "epic4-evidence-proof-missing" blockers))
    (nreverse blockers)))

(defun %build-remediation (blockers)
  "Build remediation action list from blockers."
  (declare (type list blockers))
  (let ((actions nil))
    (when (find "epic3-manifest-missing" blockers :test #'string=)
      (push "Run mcp-tui-driver T1-T6 scenarios to generate artifacts" actions))
    (when (find "epic4-manifest-missing" blockers :test #'string=)
      (push "Run Playwright S1-S6 scenarios to generate screenshots/traces" actions))
    (when (find "epic3-command-drift-detected" blockers :test #'string=)
      (push "Re-run Epic 3 with deterministic command" actions))
    (when (find "epic4-command-drift-detected" blockers :test #'string=)
      (push "Re-run Epic 4 with deterministic command" actions))
    (when (find "command-fingerprints-mismatch" blockers :test #'string=)
      (push "Verify both frameworks use canonical deterministic commands" actions))
    (nreverse actions)))

;;; ── Core Gate Evaluation ─────────────────────────────────────────────────────

(defun evaluate-unified-closure-gate (certificate)
  "Evaluate unified closure gate from dual-framework certificate.
Performs manifest integrity checks and command reference validation.
Returns UNIFIED-CLOSURE-GATE-VERDICT with readiness assessment."
  (declare (type dual-framework-certificate certificate)
           (optimize (safety 3)))
  (let* ((epic3-manifest (verify-epic3-manifest-integrity certificate))
         (epic4-manifest (verify-epic4-manifest-integrity certificate))
         (epic3-cmd (verify-epic3-command-reference certificate))
         (epic4-cmd (verify-epic4-command-reference certificate))
         (fps-match (dfc-command-fingerprints-match-p certificate))
         
         ;; Check framework pass states
         (epic3-pass-p (and epic3-manifest
                            (eq (mic-status epic3-manifest) :intact)
                            epic3-cmd
                            (eq (crc-status epic3-cmd) :intact)))
         (epic4-pass-p (and epic4-manifest
                            (eq (mic-status epic4-manifest) :intact)
                            epic4-cmd
                            (eq (crc-status epic4-cmd) :intact)))
         
         ;; Overall artifact counts
         (total (+ (mic-artifacts-checked epic3-manifest)
                   (mic-artifacts-checked epic4-manifest)))
         (intact (+ (mic-artifacts-intact epic3-manifest)
                    (mic-artifacts-intact epic4-manifest)))
         
         ;; Detect blockers
         (blockers (%detect-blockers epic3-manifest epic4-manifest epic3-cmd epic4-cmd fps-match))
         (remediation (%build-remediation blockers))
         
         ;; Final verdict
         (verdict (cond
                    ((and epic3-pass-p epic4-pass-p fps-match) :ready)
                    ((or epic3-pass-p epic4-pass-p) :partial)
                    (t :not-ready)))
         (outcome (if (eq verdict :ready) :pass :blocked)))
    
    (make-unified-closure-gate-verdict
     :gate-id (format nil "unified-gate-~D" (get-universal-time))
     :certificate-run-id (dfc-run-id certificate)
     :gate-version 1
     :readiness-verdict verdict
     :gate-outcome outcome
     :epic3-manifest-check epic3-manifest
     :epic4-manifest-check epic4-manifest
     :epic3-command-check epic3-cmd
     :epic4-command-check epic4-cmd
     :total-artifacts total
     :intact-artifacts intact
     :epic3-pass-p epic3-pass-p
     :epic4-pass-p epic4-pass-p
     :blockers blockers
     :remediation-actions remediation
     :certificate-timestamp (dfc-certificate-timestamp certificate)
     :gate-timestamp (get-universal-time))))

;;; ── JSON Serialization ───────────────────────────────────────────────────────

(defun %manifest-check->json (mc)
  "Serialize manifest integrity check to JSON."
  (declare (type manifest-integrity-check mc))
  (format nil "{\"framework\":\"~(~A~)\",\"checked\":~D,\"intact\":~D,\"missing\":~D,\"status\":\"~(~A~)\"}"
          (mic-framework mc)
          (mic-artifacts-checked mc)
          (mic-artifacts-intact mc)
          (mic-artifacts-missing mc)
          (mic-status mc)))

(defun %command-check->json (cc)
  "Serialize command reference check to JSON."
  (declare (type command-reference-check cc))
  (format nil "{\"framework\":\"~(~A~)\",\"canonical\":~A,\"fingerprint_match\":~A,\"status\":\"~(~A~)\"}"
          (crc-framework cc)
          (if (crc-command-canonical-p cc) "true" "false")
          (if (crc-fingerprint-matches-p cc) "true" "false")
          (crc-status cc)))

(defun unified-closure-gate-verdict->json (verdict)
  "Serialize unified closure gate verdict to deterministic JSON."
  (declare (type unified-closure-gate-verdict verdict))
  (with-output-to-string (out)
    (format out "{\"gate_id\":\"~A\",\"certificate_id\":\"~A\",\"version\":~D,"
            (ucgv-gate-id verdict)
            (ucgv-certificate-run-id verdict)
            (ucgv-gate-version verdict))
    
    (format out "\"readiness\":\"~(~A~)\",\"outcome\":\"~(~A~)\","
            (ucgv-readiness-verdict verdict)
            (ucgv-gate-outcome verdict))
    
    ;; Manifest checks
    (write-string "\"manifest_checks\":{" out)
    (write-string "\"epic3\":" out)
    (if (ucgv-epic3-manifest-check verdict)
        (write-string (%manifest-check->json (ucgv-epic3-manifest-check verdict)) out)
        (write-string "null" out))
    (write-string ",\"epic4\":" out)
    (if (ucgv-epic4-manifest-check verdict)
        (write-string (%manifest-check->json (ucgv-epic4-manifest-check verdict)) out)
        (write-string "null" out))
    (write-string "}," out)
    
    ;; Command checks
    (write-string "\"command_checks\":{" out)
    (write-string "\"epic3\":" out)
    (if (ucgv-epic3-command-check verdict)
        (write-string (%command-check->json (ucgv-epic3-command-check verdict)) out)
        (write-string "null" out))
    (write-string ",\"epic4\":" out)
    (if (ucgv-epic4-command-check verdict)
        (write-string (%command-check->json (ucgv-epic4-command-check verdict)) out)
        (write-string "null" out))
    (write-string "}," out)
    
    ;; Summary
    (format out "\"summary\":{\"total_artifacts\":~D,\"intact_artifacts\":~D,\"epic3_pass\":~A,\"epic4_pass\":~A},"
            (ucgv-total-artifacts verdict)
            (ucgv-intact-artifacts verdict)
            (if (ucgv-epic3-pass-p verdict) "true" "false")
            (if (ucgv-epic4-pass-p verdict) "true" "false"))
    
    ;; Blockers
    (write-string "\"blockers\":[" out)
    (loop for b in (ucgv-blockers verdict) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" b)))
    
    ;; Remediation
    (write-string "],\"remediation\":[" out)
    (loop for r in (ucgv-remediation-actions verdict) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" r)))
    
    ;; Timestamps
    (format out "],\"timestamps\":{\"certificate\":~D,\"gate\":~D}"
            (ucgv-certificate-timestamp verdict)
            (ucgv-gate-timestamp verdict))
    
    (format out ",\"policy_note\":\"~A\"}" (ucgv-policy-note verdict))))

;;; ── CLI entry point ──────────────────────────────────────────────────────────

(defun run-unified-closure-gate (epic3-artifact-root epic4-artifact-root output-path)
  "Run unified closure gate on Epic 3 and Epic 4 artifacts and write JSON to OUTPUT-PATH."
  (declare (type string epic3-artifact-root epic4-artifact-root output-path))
  ;; Bootstrap dossiers and certificate
  (let* ((epic3-matrix (make-tui-contract-matrix
                        :contracts (mapcar (lambda (sid)
                                             (make-tui-contract-row
                                              :scenario-id sid
                                              :command *tui-deterministic-command*
                                              :command-hash (sxhash *tui-deterministic-command*)
                                              :transcript-hash 0))
                                           '("T1" "T2" "T3" "T4" "T5" "T6"))))
         (epic3-ledger (compile-t1-t6-witness-ledger epic3-matrix epic3-artifact-root))
         (epic3-journal (make-empty-journal))
         (epic3-verdict (make-t1-t6-closure-verdict
                         :verdict :incomplete
                         :command-canonical-p t
                         :complete-p nil
                         :findings nil
                         :pack-hash (format nil "bootstrap-~D" (get-universal-time))
                         :assessed-at (format nil "~D" (get-universal-time))))
         (epic3-dossier (compile-epic3-closure-dossier epic3-ledger epic3-journal epic3-verdict))
         
         (epic4-replay (compile-playwright-replay-table epic4-artifact-root *playwright-canonical-command*))
         (epic4-merger (merge-playwright-attestations->envelope nil))
         (epic4-attestation (compile-epic4-closure-attestation epic4-replay epic4-merger))
         (epic4-dossier (compile-epic4-evidence-dossier epic4-attestation))
         
         (certificate (compile-dual-framework-certificate epic3-dossier epic4-dossier))
         (gate-verdict (evaluate-unified-closure-gate certificate))
         (json (unified-closure-gate-verdict->json gate-verdict)))
    
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string json s))
    
    (format t "~&Unified Closure Gate Verdict: ~A~%" (ucgv-readiness-verdict gate-verdict))
    (format t "  Gate Outcome: ~A~%" (ucgv-gate-outcome gate-verdict))
    (format t "  Epic 3 Pass: ~A~%" (ucgv-epic3-pass-p gate-verdict))
    (format t "  Epic 4 Pass: ~A~%" (ucgv-epic4-pass-p gate-verdict))
    (format t "  Artifacts: ~D/~D intact~%"
            (ucgv-intact-artifacts gate-verdict)
            (ucgv-total-artifacts gate-verdict))
    (format t "  Blockers: ~D~%" (length (ucgv-blockers gate-verdict)))
    (format t "  Written to: ~A~%" output-path)
    gate-verdict))
