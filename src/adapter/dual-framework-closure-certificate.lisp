;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; dual-framework-closure-certificate.lisp — typed dual-framework closure emitter
;;; Bead: agent-orrery-l8nv
;;;
;;; Consumes Epic 3 mcp-tui-driver T1-T6 closure dossier and Epic 4 Playwright
;;; S1-S6 evidence dossier outputs and emits a single deterministic closure
;;; certificate for release/reporting gates. Fail-closed: any missing evidence
;;; or command drift produces :OPEN verdict with full rationale.

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype certificate-verdict ()
  '(member :closed :open))

(deftype framework-status ()
  '(member :complete :partial :incomplete :none))

(deftype rationale-issue-type ()
  '(member :missing-evidence :command-drift :artifact-mismatch :incomplete :missing-dossier :coverage-gap))

(deftype framework-label ()
  '(member :epic3 :epic4 :both))

;;; ── Supporting Structures ────────────────────────────────────────────────────

(defstruct (epic3-evidence-proof (:conc-name e3ep-))
  "Evidence proof extracted from Epic 3 closure dossier."
  (dossier-run-id "" :type string)
  (scenarios-complete 0 :type integer)
  (scenarios-total 6 :type integer)
  (coverage 0.0 :type single-float)
  (artifacts-present-p nil :type boolean)
  (verdict :open :type (member :closed :open)))

(defstruct (epic4-evidence-proof (:conc-name e4ep-))
  "Evidence proof extracted from Epic 4 evidence dossier."
  (dossier-run-id "" :type string)
  (scenarios-complete 0 :type integer)
  (scenarios-total 6 :type integer)
  (coverage 0.0 :type single-float)
  (screenshots-present-p nil :type boolean)
  (traces-present-p nil :type boolean)
  (verdict :open :type (member :closed :open)))

(defstruct (rationale-entry (:conc-name re-))
  "Single rationale entry explaining why certificate is open."
  (framework :unknown :type framework-label)
  (issue-type :incomplete :type rationale-issue-type)
  (description "" :type string)
  (blocking-p nil :type boolean))

(defstruct (artifact-rollup-entry (:conc-name are-))
  "Unified artifact digest entry from both frameworks."
  (framework :unknown :type framework-label)
  (path "" :type string)
  (digest "" :type string))

;;; ── Main Certificate Structure ───────────────────────────────────────────────

(defstruct (dual-framework-certificate (:conc-name dfc-))
  "Machine-checkable closure certificate for dual-framework release gates."
  ;; Identity
  (run-id "" :type string)
  (certificate-version 1 :type integer)
  
  ;; Framework evidence proofs
  (epic3-evidence-proof nil :type (or null epic3-evidence-proof))
  (epic4-evidence-proof nil :type (or null epic4-evidence-proof))
  
  ;; Combined state
  (framework-status :incomplete :type framework-status)
  (closure-verdict :open :type certificate-verdict)
  
  ;; Rollup metrics
  (total-scenarios 12 :type integer)
  (scenarios-passing 0 :type integer)
  (scenario-coverage 0.0 :type single-float)
  
  ;; Deterministic command fingerprints
  (epic3-command-fingerprint 0 :type integer)
  (epic4-command-fingerprint 0 :type integer)
  (command-fingerprints-match nil :type boolean)
  
  ;; Artifact digest rollup
  (artifact-rollup nil :type list)
  
  ;; Fail-closed rationale
  (fail-closed-rationale nil :type list)
  (blocking-issues nil :type list)
  
  ;; Timestamps
  (epic3-timestamp 0 :type integer)
  (epic4-timestamp 0 :type integer)
  (certificate-timestamp 0 :type integer)
  
  ;; Policy note
  (policy-note "Both Epic 3 mcp-tui-driver T1-T6 and Epic 4 Playwright S1-S6 evidence required for closure." :type string))

;;; ── Declaims ─────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (epic3-closure-dossier) (values epic3-evidence-proof &optional))
        extract-epic3-proof)
 (ftype (function (epic4-evidence-dossier) (values epic4-evidence-proof &optional))
        extract-epic4-proof)
 (ftype (function (epic3-closure-dossier epic4-evidence-dossier) (values list &optional))
        merge-artifact-digests)
 (ftype (function (epic3-evidence-proof epic4-evidence-proof
                 epic3-closure-dossier epic4-evidence-dossier)
          (values list &optional))
        build-fail-closed-rationale)
 (ftype (function (epic3-closure-dossier epic4-evidence-dossier)
          (values dual-framework-certificate &optional))
        compile-dual-framework-certificate)
 (ftype (function (dual-framework-certificate) (values string &optional))
        dual-framework-certificate->json))

;;; ── Internal utilities ───────────────────────────────────────────────────────

(defun extract-epic3-proof (dossier)
  "Extract evidence proof from Epic 3 closure dossier."
  (declare (type epic3-closure-dossier dossier)
           (optimize (safety 3)))
  (let* ((records (ecd-records dossier))
         (passing (count-if #'esr-artifacts-present-p records))
         (all-present-p (= passing 6))
         (coverage (ecd-scenario-coverage dossier)))
    (make-epic3-evidence-proof
     :dossier-run-id (ecd-run-id dossier)
     :scenarios-complete passing
     :scenarios-total 6
     :coverage coverage
     :artifacts-present-p all-present-p
     :verdict (if (eq (ecd-closure-verdict dossier) :closed) :closed :open))))

(defun extract-epic4-proof (dossier)
  "Extract evidence proof from Epic 4 evidence dossier."
  (declare (type epic4-evidence-dossier dossier)
           (optimize (safety 3)))
  (let* ((records (e4ed-records dossier))
         (passing (count-if #'e4sr-evidence-complete-p records))
         (all-screenshots (every (lambda (r) (> (length (e4sr-screenshot-digest r)) 0)) records))
         (all-traces (every (lambda (r) (> (length (e4sr-trace-digest r)) 0)) records)))
    (make-epic4-evidence-proof
     :dossier-run-id (e4ed-run-id dossier)
     :scenarios-complete passing
     :scenarios-total 6
     :coverage (e4ed-scenario-coverage dossier)
     :screenshots-present-p all-screenshots
     :traces-present-p all-traces
     :verdict (if (eq (e4ed-closure-verdict dossier) :closed) :closed :open))))

(defun merge-artifact-digests (epic3-dossier epic4-dossier)
  "Merge artifact digests from both frameworks into unified rollup."
  (declare (type epic3-closure-dossier epic3-dossier)
           (type epic4-evidence-dossier epic4-dossier)
           (optimize (safety 3)))
  (let ((rollup nil))
    ;; Epic 3 artifacts
    (dolist (entry (ecd-artifact-digest-map epic3-dossier))
      (push (make-artifact-rollup-entry
             :framework :epic3
             :path (ade-path entry)
             :digest (ade-digest entry))
            rollup))
    ;; Epic 4 screenshots
    (dolist (pair (e4ed-screenshot-digests epic4-dossier))
      (let ((sid (car pair))
            (digest (cdr pair)))
        (when (> (length digest) 0)
          (push (make-artifact-rollup-entry
                 :framework :epic4
                 :path (format nil "e2e/screenshots/~A.png" sid)
                 :digest digest)
                rollup))))
    ;; Epic 4 traces
    (dolist (pair (e4ed-trace-digests epic4-dossier))
      (let ((sid (car pair))
            (digest (cdr pair)))
        (when (> (length digest) 0)
          (push (make-artifact-rollup-entry
                 :framework :epic4
                 :path (format nil "e2e/traces/~A.zip" sid)
                 :digest digest)
            rollup))))
    (nreverse rollup)))

(defun %make-rationale (framework issue-type description blocking-p)
  "Construct a single rationale entry."
  (declare (type framework-label framework)
           (type rationale-issue-type issue-type)
           (type string description)
           (type boolean blocking-p))
  (make-rationale-entry
   :framework framework
   :issue-type issue-type
   :description description
   :blocking-p blocking-p))

(defun build-fail-closed-rationale (epic3-proof epic4-proof epic3-dossier epic4-dossier)
  "Build fail-closed rationale list from framework proofs."
  (declare (type (or null epic3-evidence-proof) epic3-proof)
           (type (or null epic4-evidence-proof) epic4-proof)
           (type (or null epic3-closure-dossier) epic3-dossier)
           (type (or null epic4-evidence-dossier) epic4-dossier)
           (optimize (safety 3)))
  (let ((rationale nil))
    ;; Missing Epic 3 dossier
    (when (or (null epic3-dossier) (null epic3-proof))
      (push (%make-rationale :epic3 :missing-dossier
                             "Epic 3 closure dossier missing or incomplete" t)
            rationale))
    
    ;; Missing Epic 4 dossier
    (when (or (null epic4-dossier) (null epic4-proof))
      (push (%make-rationale :epic4 :missing-dossier
                             "Epic 4 evidence dossier missing or incomplete" t)
            rationale))
    
    ;; Epic 3 incomplete coverage
    (when (and epic3-proof (< (e3ep-scenarios-complete epic3-proof) 6))
      (push (%make-rationale :epic3 :coverage-gap
                             (format nil "Epic 3: ~D/~D scenarios complete"
                                     (e3ep-scenarios-complete epic3-proof)
                                     (e3ep-scenarios-total epic3-proof))
                             t)
            rationale))
    
    ;; Epic 3 missing artifacts
    (when (and epic3-proof (not (e3ep-artifacts-present-p epic3-proof)))
      (push (%make-rationale :epic3 :missing-evidence
                             "Epic 3: artifact evidence incomplete" t)
            rationale))
    
    ;; Epic 3 open verdict
    (when (and epic3-proof (eq (e3ep-verdict epic3-proof) :open))
      (push (%make-rationale :epic3 :incomplete
                             "Epic 3: closure verdict is OPEN" t)
            rationale))
    
    ;; Epic 4 incomplete coverage
    (when (and epic4-proof (< (e4ep-scenarios-complete epic4-proof) 6))
      (push (%make-rationale :epic4 :coverage-gap
                             (format nil "Epic 4: ~D/~D scenarios complete"
                                     (e4ep-scenarios-complete epic4-proof)
                                     (e4ep-scenarios-total epic4-proof))
                             t)
            rationale))
    
    ;; Epic 4 missing screenshots
    (when (and epic4-proof (not (e4ep-screenshots-present-p epic4-proof)))
      (push (%make-rationale :epic4 :missing-evidence
                             "Epic 4: screenshot evidence incomplete" t)
            rationale))
    
    ;; Epic 4 missing traces
    (when (and epic4-proof (not (e4ep-traces-present-p epic4-proof)))
      (push (%make-rationale :epic4 :missing-evidence
                             "Epic 4: trace evidence incomplete" t)
            rationale))
    
    ;; Epic 4 open verdict
    (when (and epic4-proof (eq (e4ep-verdict epic4-proof) :open))
      (push (%make-rationale :epic4 :incomplete
                             "Epic 4: closure verdict is OPEN" t)
            rationale))
    
    ;; Command fingerprint drift
    (when (and epic3-dossier epic4-dossier)
      (let ((fp3 (ecd-command-fingerprint epic3-dossier))
            (fp4 (e4ed-command-fingerprint epic4-dossier)))
        (when (and (plusp fp3) (plusp fp4) (/= fp3 fp4))
          (push (%make-rationale :both :command-drift
                                 (format nil "Command fingerprints differ: Epic3=~D, Epic4=~D" fp3 fp4)
                                 t)
                rationale))))
    
    (nreverse rationale)))

;;; ── Core certificate compiler ────────────────────────────────────────────────

(defun compile-dual-framework-certificate (epic3-dossier epic4-dossier)
  "Compile dual-framework closure certificate from Epic 3 and Epic 4 dossiers.
Returns a DUAL-FRAMEWORK-CERTIFICATE with deterministic JSON shape.
Fail-closed: any missing evidence produces :OPEN verdict with rationale."
  (declare (type (or null epic3-closure-dossier) epic3-dossier)
           (type (or null epic4-evidence-dossier) epic4-dossier)
           (optimize (safety 3)))
  (let* ((epic3-proof (when epic3-dossier (extract-epic3-proof epic3-dossier)))
         (epic4-proof (when epic4-dossier (extract-epic4-proof epic4-dossier)))
         
         ;; Determine framework status
         (epic3-closed-p (and epic3-proof (eq (e3ep-verdict epic3-proof) :closed)))
         (epic4-closed-p (and epic4-proof (eq (e4ep-verdict epic4-proof) :closed)))
         (framework-status (cond
                             ((and epic3-closed-p epic4-closed-p) :complete)
                             ((or epic3-closed-p epic4-closed-p) :partial)
                             ((and epic3-proof epic4-proof) :incomplete)
                             (t :none)))
         
         ;; Rollup metrics
         (epic3-passing (if epic3-proof (e3ep-scenarios-complete epic3-proof) 0))
         (epic4-passing (if epic4-proof (e4ep-scenarios-complete epic4-proof) 0))
         (scenarios-passing (+ epic3-passing epic4-passing))
         (coverage (/ scenarios-passing 12.0))
         
         ;; Command fingerprints
         (fp3 (if epic3-dossier (ecd-command-fingerprint epic3-dossier) 0))
         (fp4 (if epic4-dossier (e4ed-command-fingerprint epic4-dossier) 0))
         (fps-match (and (plusp fp3) (plusp fp4) (= fp3 fp4)))
         
         ;; Artifact rollup
         (artifact-rollup (if (and epic3-dossier epic4-dossier)
                              (merge-artifact-digests epic3-dossier epic4-dossier)
                            nil))
         
         ;; Build rationale
         (rationale (build-fail-closed-rationale
                     epic3-proof epic4-proof epic3-dossier epic4-dossier))
         
         ;; Blocking issues
         (blocking (mapcar #'re-description
                           (remove-if-not #'re-blocking-p rationale)))
         
         ;; Final verdict: fail-closed unless all conditions met
         (verdict (if (and (eq framework-status :complete)
                           fps-match)
                      :closed
                      :open)))
    
    (make-dual-framework-certificate
     :run-id (format nil "dual-cert-~D" (get-universal-time))
     :certificate-version 1
     :epic3-evidence-proof epic3-proof
     :epic4-evidence-proof epic4-proof
     :framework-status framework-status
     :closure-verdict verdict
     :total-scenarios 12
     :scenarios-passing scenarios-passing
     :scenario-coverage coverage
     :epic3-command-fingerprint fp3
     :epic4-command-fingerprint fp4
     :command-fingerprints-match fps-match
     :artifact-rollup artifact-rollup
     :fail-closed-rationale rationale
     :blocking-issues blocking
     :epic3-timestamp (if epic3-dossier (ecd-timestamp epic3-dossier) 0)
     :epic4-timestamp (if epic4-dossier (e4ed-timestamp epic4-dossier) 0)
     :certificate-timestamp (get-universal-time))))

;;; ── JSON serialization ───────────────────────────────────────────────────────

(defun %rationale-entry->json (r)
  "Serialize RATIONALE-ENTRY to JSON string."
  (declare (type rationale-entry r))
  (format nil "{\"framework\":\"~(~A~)\",\"issue\":\"~(~A~)\",\"description\":\"~A\",\"blocking\":~A}"
          (re-framework r)
          (re-issue-type r)
          (re-description r)
          (if (re-blocking-p r) "true" "false")))

(defun %artifact-rollup->json (e)
  "Serialize ARTIFACT-ROLLUP-ENTRY to JSON string."
  (declare (type artifact-rollup-entry e))
  (format nil "{\"framework\":\"~(~A~)\",\"path\":\"~A\",\"digest\":\"~A\"}"
          (are-framework e)
          (are-path e)
          (are-digest e)))

(defun %epic3-proof->json (p)
  "Serialize EPIC3-EVIDENCE-PROOF to JSON string."
  (declare (type epic3-evidence-proof p))
  (format nil "{\"run_id\":\"~A\",\"scenarios_complete\":~D,\"scenarios_total\":~D,\"coverage\":~4,2F,\"artifacts_present\":~A,\"verdict\":\"~(~A~)\"}"
          (e3ep-dossier-run-id p)
          (e3ep-scenarios-complete p)
          (e3ep-scenarios-total p)
          (e3ep-coverage p)
          (if (e3ep-artifacts-present-p p) "true" "false")
          (e3ep-verdict p)))

(defun %epic4-proof->json (p)
  "Serialize EPIC4-EVIDENCE-PROOF to JSON string."
  (declare (type epic4-evidence-proof p))
  (format nil "{\"run_id\":\"~A\",\"scenarios_complete\":~D,\"scenarios_total\":~D,\"coverage\":~4,2F,\"screenshots_present\":~A,\"traces_present\":~A,\"verdict\":\"~(~A~)\"}"
          (e4ep-dossier-run-id p)
          (e4ep-scenarios-complete p)
          (e4ep-scenarios-total p)
          (e4ep-coverage p)
          (if (e4ep-screenshots-present-p p) "true" "false")
          (if (e4ep-traces-present-p p) "true" "false")
          (e4ep-verdict p)))

(defun dual-framework-certificate->json (cert)
  "Serialize DUAL-FRAMEWORK-CERTIFICATE to deterministic JSON."
  (declare (type dual-framework-certificate cert))
  (with-output-to-string (out)
    ;; Header
    (format out "{\"run_id\":\"~A\",\"version\":~D,\"verdict\":\"~(~A~)\",\"framework_status\":\"~(~A~)\","
            (dfc-run-id cert)
            (dfc-certificate-version cert)
            (dfc-closure-verdict cert)
            (dfc-framework-status cert))
    
    ;; Rollup metrics
    (format out "\"total_scenarios\":~D,\"scenarios_passing\":~D,\"coverage\":~4,2F,"
            (dfc-total-scenarios cert)
            (dfc-scenarios-passing cert)
            (dfc-scenario-coverage cert))
    
    ;; Epic 3 proof
    (write-string "\"epic3\":" out)
    (if (dfc-epic3-evidence-proof cert)
        (write-string (%epic3-proof->json (dfc-epic3-evidence-proof cert)) out)
        (write-string "null" out))
    
    ;; Epic 4 proof
    (write-string ",\"epic4\":" out)
    (if (dfc-epic4-evidence-proof cert)
        (write-string (%epic4-proof->json (dfc-epic4-evidence-proof cert)) out)
        (write-string "null" out))
    
    ;; Command fingerprints
    (format out ",\"command_fingerprints\":{\"epic3\":~D,\"epic4\":~D,\"match\":~A}"
            (dfc-epic3-command-fingerprint cert)
            (dfc-epic4-command-fingerprint cert)
            (if (dfc-command-fingerprints-match cert) "true" "false"))
    
    ;; Artifact rollup
    (write-string ",\"artifact_rollup\":[" out)
    (loop for e in (dfc-artifact-rollup cert) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%artifact-rollup->json e) out)))
    
    ;; Rationale
    (write-string "],\"rationale\":[" out)
    (loop for r in (dfc-fail-closed-rationale cert) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%rationale-entry->json r) out)))
    
    ;; Blocking issues
    (write-string "],\"blocking_issues\":[" out)
    (loop for issue in (dfc-blocking-issues cert) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" issue)))
    
    ;; Timestamps
    (format out "],\"timestamps\":{\"epic3\":~D,\"epic4\":~D,\"certificate\":~D}"
            (dfc-epic3-timestamp cert)
            (dfc-epic4-timestamp cert)
            (dfc-certificate-timestamp cert))
    
    ;; Policy note
    (format out ",\"policy_note\":\"~A\"}" (dfc-policy-note cert))))

;;; ── CLI entry point ──────────────────────────────────────────────────────────

(defun run-dual-framework-certificate-compiler (epic3-artifact-root epic4-artifact-root output-path)
  "Run the dual-framework certificate compiler and write JSON to OUTPUT-PATH.
EPIC3-ARTIFACT-ROOT: path to Epic 3 mcp-tui-driver artifacts.
EPIC4-ARTIFACT-ROOT: path to Epic 4 Playwright artifacts."
  (declare (type string epic3-artifact-root epic4-artifact-root output-path))
  ;; Bootstrap dossiers (in production, would deserialize from JSON files)
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
         (json (dual-framework-certificate->json certificate)))
    
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string json s))
    
    (format t "~&Dual-Framework Closure Certificate: ~A~%" (dfc-closure-verdict certificate))
    (format t "  Framework Status: ~A~%" (dfc-framework-status certificate))
    (format t "  Scenarios Passing: ~D/~D~%"
            (dfc-scenarios-passing certificate)
            (dfc-total-scenarios certificate))
    (format t "  Coverage: ~4,2F%~%" (* 100 (dfc-scenario-coverage certificate)))
    (format t "  Command Fingerprints Match: ~A~%" (dfc-command-fingerprints-match certificate))
    (format t "  Rationale Entries: ~D~%" (length (dfc-fail-closed-rationale certificate)))
    (format t "  Blocking Issues: ~D~%" (length (dfc-blocking-issues certificate)))
    (format t "  Written to: ~A~%" output-path)
    certificate))
