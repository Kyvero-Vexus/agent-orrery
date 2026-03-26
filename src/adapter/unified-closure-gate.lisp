;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; unified-closure-gate.lisp — typed unified closure gate for Epic 3/4 evidence
;;; Bead: agent-orrery-2wb
;;;
;;; Consumes Epic 3 mcp-tui-driver T1-T6 evidence and Epic 4 Playwright S1-S6
;;; evidence, producing a single machine-checkable readiness verdict.
;;; Fail-closed: any missing evidence, command drift, or artifact gaps produce
;;; :OPEN verdict with comprehensive rationale.

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype unified-verdict-status ()
  '(member :closed :open))

(deftype framework-label ()
  '(member :epic3 :epic4 :both))

(deftype closure-issue-category ()
  '(member :missing-dossier :missing-evidence :command-drift 
           :artifact-mismatch :incomplete-coverage :coverage-gap))

;;; ── Supporting Structures ────────────────────────────────────────────────────

(defstruct (closure-rationale-entry (:conc-name cre-))
  "Single rationale entry explaining why closure verdict is open."
  (framework :unknown :type framework-label)
  (category :incomplete-coverage :type closure-issue-category)
  (description "" :type string)
  (blocking-p nil :type boolean))

;;; ── Main Verdict Structure ───────────────────────────────────────────────────

(defstruct (unified-closure-verdict (:conc-name ucv-))
  "Machine-checkable unified closure verdict for Epic 3 + Epic 4 evidence gates.
  
  This structure encapsulates the complete closure state for both frameworks,
  including evidence dossiers, command fingerprints, artifact integrity checks,
  and a fail-closed rationale when evidence is incomplete."
  
  ;; Identity
  (run-id "" :type string)
  (schema-version "ucv-v1" :type string)
  
  ;; Primary verdict
  (pass-p nil :type boolean)
  (verdict :open :type unified-verdict-status)
  
  ;; Framework evidence dossiers
  (epic3-dossier nil :type (or null epic3-closure-dossier))
  (epic4-dossier nil :type (or null epic4-evidence-dossier))
  (certificate nil :type (or null dual-framework-certificate))
  
  ;; Deterministic command verification
  (epic3-command "" :type string)
  (epic4-command "" :type string)
  (epic3-command-fingerprint 0 :type integer)
  (epic4-command-fingerprint 0 :type integer)
  (commands-match-p nil :type boolean)
  (epic3-command-canonical-p nil :type boolean)
  (epic4-command-canonical-p nil :type boolean)
  
  ;; Artifact manifest integrity
  (epic3-artifacts-valid-p nil :type boolean)
  (epic4-artifacts-valid-p nil :type boolean)
  (epic3-artifact-count 0 :type integer)
  (epic4-artifact-count 0 :type integer)
  (total-artifact-count 0 :type integer)
  
  ;; Coverage metrics
  (epic3-scenarios-total 6 :type integer)
  (epic3-scenarios-complete 0 :type integer)
  (epic4-scenarios-total 6 :type integer)
  (epic4-scenarios-complete 0 :type integer)
  (total-scenarios 12 :type integer)
  (scenarios-passing 0 :type integer)
  (coverage-percentage 0.0 :type single-float)
  
  ;; Fail-closed rationale
  (rationale nil :type list)              ; list of closure-rationale-entry
  (blocking-issues nil :type list)        ; list of strings
  
  ;; Timestamps
  (epic3-timestamp 0 :type integer)
  (epic4-timestamp 0 :type integer)
  (verdict-timestamp 0 :type integer)
  
  ;; Policy
  (policy-note "Unified closure requires complete Epic 3 mcp-tui-driver T1-T6 evidence and Epic 4 Playwright S1-S6 evidence with deterministic command references and artifact manifest integrity." :type string))

;;; ── Declaims ─────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string string) (values boolean &optional))
        validate-epic3-artifact-manifest)
 (ftype (function (string string) (values boolean &optional))
        validate-epic4-artifact-manifest)
 (ftype (function (string) (values integer &optional))
        count-epic3-artifacts)
 (ftype (function (string) (values integer &optional))
        count-epic4-artifacts)
 (ftype (function (epic3-closure-dossier epic4-evidence-dossier
                 boolean boolean string string)
          (values list &optional))
        build-unified-closure-rationale)
 (ftype (function (string string string string)
          (values unified-closure-verdict &optional))
        evaluate-unified-closure-gate)
 (ftype (function (unified-closure-verdict) (values string &optional))
        unified-closure-verdict->json)
 (ftype (function (closure-rationale-entry) (values string &optional))
        %cre->json))

;;; ── Artifact Manifest Validation ─────────────────────────────────────────────

(defun validate-epic3-artifact-manifest (artifacts-dir deterministic-command)
  "Validate Epic 3 mcp-tui-driver artifact manifest integrity.
Returns T if all required T1-T6 artifacts exist and command matches."
  (declare (type string artifacts-dir deterministic-command)
           (optimize (safety 3)))
  (let* ((canonical-cmd *mcp-tui-deterministic-command*)
         (cmd-match (string= deterministic-command canonical-cmd))
         (required-scenarios '("T1" "T2" "T3" "T4" "T5" "T6"))
         (all-present t))
    ;; Check command matches
    (unless cmd-match
      (return-from validate-epic3-artifact-manifest nil))
    ;; Check each scenario has artifacts
    (dolist (sid required-scenarios)
      (let* ((screenshot-path (format nil "~A/~A.png" artifacts-dir sid))
             (transcript-path (format nil "~A/~A.txt" artifacts-dir sid)))
        (unless (and (probe-file screenshot-path)
                     (probe-file transcript-path))
          (setf all-present nil))))
    all-present))

(defun validate-epic4-artifact-manifest (artifacts-dir deterministic-command)
  "Validate Epic 4 Playwright artifact manifest integrity.
Returns T if all required S1-S6 artifacts exist and command matches."
  (declare (type string artifacts-dir deterministic-command)
           (optimize (safety 3)))
  (let* ((canonical-cmd *playwright-deterministic-command*)
         (cmd-match (string= deterministic-command canonical-cmd))
         (required-scenarios '("S1" "S2" "S3" "S4" "S5" "S6"))
         (all-present t))
    ;; Check command matches
    (unless cmd-match
      (return-from validate-epic4-artifact-manifest nil))
    ;; Check each scenario has artifacts
    (dolist (sid required-scenarios)
      (let* ((screenshot-path (format nil "~A/screenshots/~A.png" artifacts-dir sid))
             (trace-path (format nil "~A/traces/~A.zip" artifacts-dir sid)))
        (unless (and (probe-file screenshot-path)
                     (probe-file trace-path))
          (setf all-present nil))))
    all-present))

(defun count-epic3-artifacts (artifacts-dir)
  "Count Epic 3 artifacts in directory."
  (declare (type string artifacts-dir)
           (optimize (safety 3)))
  (let ((count 0))
    (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
      (let* ((screenshot-path (format nil "~A/~A.png" artifacts-dir sid))
             (transcript-path (format nil "~A/~A.txt" artifacts-dir sid)))
        (when (probe-file screenshot-path) (incf count))
        (when (probe-file transcript-path) (incf count))))
    count))

(defun count-epic4-artifacts (artifacts-dir)
  "Count Epic 4 artifacts in directory."
  (declare (type string artifacts-dir)
           (optimize (safety 3)))
  (let ((count 0))
    (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
      (let* ((screenshot-path (format nil "~A/screenshots/~A.png" artifacts-dir sid))
             (trace-path (format nil "~A/traces/~A.zip" artifacts-dir sid)))
        (when (probe-file screenshot-path) (incf count))
        (when (probe-file trace-path) (incf count))))
    count))

;;; ── Rationale Builder ────────────────────────────────────────────────────────

(defun %make-rationale (framework category description blocking-p)
  "Construct a single rationale entry."
  (declare (type framework-label framework)
           (type closure-issue-category category)
           (type string description)
           (type boolean blocking-p))
  (make-closure-rationale-entry
   :framework framework
   :category category
   :description description
   :blocking-p blocking-p))

(defun build-unified-closure-rationale 
    (epic3-dossier epic4-dossier 
     epic3-artifacts-valid epic4-artifacts-valid
     epic3-command epic4-command)
  "Build fail-closed rationale list from dossier and validation state."
  (declare (type (or null epic3-closure-dossier) epic3-dossier)
           (type (or null epic4-evidence-dossier) epic4-dossier)
           (type boolean epic3-artifacts-valid epic4-artifacts-valid)
           (type string epic3-command epic4-command)
           (optimize (safety 3)))
  (let ((rationale nil))
    
    ;; Missing Epic 3 dossier
    (when (null epic3-dossier)
      (push (%make-rationale :epic3 :missing-dossier
                             "Epic 3 closure dossier missing or compilation failed" t)
            rationale))
    
    ;; Missing Epic 4 dossier
    (when (null epic4-dossier)
      (push (%make-rationale :epic4 :missing-dossier
                             "Epic 4 evidence dossier missing or compilation failed" t)
            rationale))
    
    ;; Epic 3 command drift
    (when (and epic3-dossier
               (not (string= epic3-command *mcp-tui-deterministic-command*)))
      (push (%make-rationale :epic3 :command-drift
                             (format nil "Epic 3 command drift: expected '~A', got '~A'"
                                     *mcp-tui-deterministic-command* epic3-command)
                             t)
            rationale))
    
    ;; Epic 4 command drift
    (when (and epic4-dossier
               (not (string= epic4-command *playwright-deterministic-command*)))
      (push (%make-rationale :epic4 :command-drift
                             (format nil "Epic 4 command drift: expected '~A', got '~A'"
                                     *playwright-deterministic-command* epic4-command)
                             t)
            rationale))
    
    ;; Epic 3 artifact manifest invalid
    (when (and epic3-dossier (not epic3-artifacts-valid))
      (push (%make-rationale :epic3 :artifact-mismatch
                             "Epic 3 artifact manifest validation failed: missing or incomplete artifacts" t)
            rationale))
    
    ;; Epic 4 artifact manifest invalid
    (when (and epic4-dossier (not epic4-artifacts-valid))
      (push (%make-rationale :epic4 :artifact-mismatch
                             "Epic 4 artifact manifest validation failed: missing or incomplete artifacts" t)
            rationale))
    
    ;; Epic 3 incomplete coverage
    (when (and epic3-dossier 
               (< (ecd-scenario-coverage epic3-dossier) 1.0))
      (push (%make-rationale :epic3 :coverage-gap
                             (format nil "Epic 3 incomplete coverage: ~,2F% (~D/~D scenarios)"
                                     (* 100 (ecd-scenario-coverage epic3-dossier))
                                     (count-if #'esr-artifacts-present-p (ecd-records epic3-dossier))
                                     6)
                             t)
            rationale))
    
    ;; Epic 3 open verdict
    (when (and epic3-dossier (eq (ecd-closure-verdict epic3-dossier) :open))
      (push (%make-rationale :epic3 :incomplete-coverage
                             "Epic 3 closure dossier verdict is OPEN" t)
            rationale))
    
    ;; Epic 4 incomplete coverage
    (when (and epic4-dossier
               (< (e4ed-scenario-coverage epic4-dossier) 1.0))
      (push (%make-rationale :epic4 :coverage-gap
                             (format nil "Epic 4 incomplete coverage: ~,2F% (~D/~D scenarios)"
                                     (* 100 (e4ed-scenario-coverage epic4-dossier))
                                     (count-if #'e4sr-evidence-complete-p (e4ed-records epic4-dossier))
                                     6)
                             t)
            rationale))
    
    ;; Epic 4 open verdict
    (when (and epic4-dossier (eq (e4ed-closure-verdict epic4-dossier) :open))
      (push (%make-rationale :epic4 :incomplete-coverage
                             "Epic 4 evidence dossier verdict is OPEN" t)
            rationale))
    
    (nreverse rationale)))

;;; ── Core Gate Evaluator ───────────────────────────────────────────────────────

(defun evaluate-unified-closure-gate 
    (epic3-artifacts-dir epic3-command 
     epic4-artifacts-dir epic4-command)
  "Evaluate unified closure gate for Epic 3 + Epic 4 evidence.
  
  Parameters:
    EPIC3-ARTIFACTS-DIR: Path to mcp-tui-driver T1-T6 artifacts
    EPIC3-COMMAND: Deterministic command used for Epic 3
    EPIC4-ARTIFACTS-DIR: Path to Playwright S1-S6 artifacts
    EPIC4-COMMAND: Deterministic command used for Epic 4
  
  Returns:
    UNIFIED-CLOSURE-VERDICT with pass/fail and comprehensive diagnostics.
    Fail-closed: returns OPEN verdict with rationale if any evidence incomplete."
  
  (declare (type string epic3-artifacts-dir epic3-command
                   epic4-artifacts-dir epic4-command)
           (optimize (safety 3)))
  
  (let* (;; Compile Epic 3 closure dossier
         (epic3-dossier 
          (handler-case
              (let* ((matrix (make-tui-contract-matrix
                              :contracts (mapcar 
                                          (lambda (sid)
                                            (make-tui-contract-row
                                             :scenario-id sid
                                             :command *mcp-tui-deterministic-command*
                                             :command-hash (sxhash *mcp-tui-deterministic-command*)
                                             :transcript-hash 0))
                                          '("T1" "T2" "T3" "T4" "T5" "T6"))))
                     (ledger (compile-t1-t6-witness-ledger matrix epic3-artifacts-dir))
                     (journal (make-empty-journal))
                     (verdict (make-t1-t6-closure-verdict
                               :verdict :incomplete
                               :command-canonical-p t
                               :complete-p nil
                               :findings nil
                               :pack-hash (format nil "bootstrap-~D" (get-universal-time))
                               :assessed-at (format nil "~D" (get-universal-time)))))
                (compile-epic3-closure-dossier ledger journal verdict))
            (error () nil)))
         
         ;; Compile Epic 4 evidence dossier
         (epic4-dossier
          (handler-case
              (let* ((replay (compile-playwright-replay-table 
                              epic4-artifacts-dir *playwright-canonical-command*))
                     (merger (merge-playwright-attestations->envelope nil))
                     (attestation (compile-epic4-closure-attestation replay merger)))
                (compile-epic4-evidence-dossier attestation))
            (error () nil)))
         
         ;; Validate artifact manifests
         (epic3-artifacts-valid 
          (and epic3-dossier
               (validate-epic3-artifact-manifest epic3-artifacts-dir epic3-command)))
         (epic4-artifacts-valid
          (and epic4-dossier
               (validate-epic4-artifact-manifest epic4-artifacts-dir epic4-command)))
         
         ;; Count artifacts
         (epic3-artifact-count (count-epic3-artifacts epic3-artifacts-dir))
         (epic4-artifact-count (count-epic4-artifacts epic4-artifacts-dir))
         
         ;; Compile dual-framework certificate
         (certificate 
          (when (and epic3-dossier epic4-dossier)
            (compile-dual-framework-certificate epic3-dossier epic4-dossier)))
         
         ;; Command fingerprints
         (epic3-cmd-fp (command-fingerprint epic3-command))
         (epic4-cmd-fp (command-fingerprint epic4-command))
         (epic3-cmd-canonical (string= epic3-command *mcp-tui-deterministic-command*))
         (epic4-cmd-canonical (string= epic4-command *playwright-deterministic-command*))
         (cmds-match (and epic3-cmd-canonical epic4-cmd-canonical))
         
         ;; Coverage metrics
         (epic3-complete (if epic3-dossier
                             (count-if #'esr-artifacts-present-p (ecd-records epic3-dossier))
                             0))
         (epic4-complete (if epic4-dossier
                             (count-if #'e4sr-evidence-complete-p (e4ed-records epic4-dossier))
                             0))
         (scenarios-passing (+ epic3-complete epic4-complete))
         (coverage-pct (/ scenarios-passing 12.0))
         
         ;; Build rationale
         (rationale (build-unified-closure-rationale
                     epic3-dossier epic4-dossier
                     epic3-artifacts-valid epic4-artifacts-valid
                     epic3-command epic4-command))
         
         ;; Extract blocking issues
         (blocking (mapcar #'cre-description
                           (remove-if-not #'cre-blocking-p rationale)))
         
         ;; Determine final verdict
         ;; Fail-closed: must have both dossiers, valid artifacts, matching commands, closed certificate
         (pass (and epic3-dossier
                    epic4-dossier
                    certificate
                    epic3-artifacts-valid
                    epic4-artifacts-valid
                    cmds-match
                    (eq (dfc-closure-verdict certificate) :closed)))
         (verdict (if pass :closed :open)))
    
    (make-unified-closure-verdict
     :run-id (format nil "ucv-~D" (get-universal-time))
     :schema-version "ucv-v1"
     :pass-p pass
     :verdict verdict
     :epic3-dossier epic3-dossier
     :epic4-dossier epic4-dossier
     :certificate certificate
     :epic3-command epic3-command
     :epic4-command epic4-command
     :epic3-command-fingerprint epic3-cmd-fp
     :epic4-command-fingerprint epic4-cmd-fp
     :commands-match-p cmds-match
     :epic3-command-canonical-p epic3-cmd-canonical
     :epic4-command-canonical-p epic4-cmd-canonical
     :epic3-artifacts-valid-p epic3-artifacts-valid
     :epic4-artifacts-valid-p epic4-artifacts-valid
     :epic3-artifact-count epic3-artifact-count
     :epic4-artifact-count epic4-artifact-count
     :total-artifact-count (+ epic3-artifact-count epic4-artifact-count)
     :epic3-scenarios-complete epic3-complete
     :epic4-scenarios-complete epic4-complete
     :scenarios-passing scenarios-passing
     :coverage-percentage (* 100.0 coverage-pct)
     :rationale rationale
     :blocking-issues blocking
     :epic3-timestamp (if epic3-dossier (ecd-timestamp epic3-dossier) 0)
     :epic4-timestamp (if epic4-dossier (e4ed-timestamp epic4-dossier) 0)
     :verdict-timestamp (get-universal-time))))

;;; ── JSON Serialization ───────────────────────────────────────────────────────

(defun %cre->json (entry)
  "Serialize CLOSURE-RATIONALE-ENTRY to JSON string."
  (declare (type closure-rationale-entry entry))
  (format nil "{\"framework\":\"~(~A~)\",\"category\":\"~(~A~)\",\"description\":\"~A\",\"blocking\":~A}"
          (cre-framework entry)
          (cre-category entry)
          (cre-description entry)
          (if (cre-blocking-p entry) "true" "false")))

(defun unified-closure-verdict->json (verdict)
  "Serialize UNIFIED-CLOSURE-VERDICT to deterministic JSON string.
  
  Produces machine-checkable JSON with stable field ordering."
  (declare (type unified-closure-verdict verdict)
           (optimize (safety 3)))
  (with-output-to-string (out)
    ;; Header
    (format out "{\"schema\":\"~A\",\"run_id\":\"~A\","
            (ucv-schema-version verdict)
            (ucv-run-id verdict))
    
    ;; Primary verdict
    (format out "\"pass\":~A,\"verdict\":\"~(~A~)\","
            (if (ucv-pass-p verdict) "true" "false")
            (ucv-verdict verdict))
    
    ;; Commands
    (format out "\"commands\":{")
    (format out "\"epic3\":{\"command\":\"~A\",\"fingerprint\":~D,\"canonical\":~A},"
            (ucv-epic3-command verdict)
            (ucv-epic3-command-fingerprint verdict)
            (if (ucv-epic3-command-canonical-p verdict) "true" "false"))
    (format out "\"epic4\":{\"command\":\"~A\",\"fingerprint\":~D,\"canonical\":~A},"
            (ucv-epic4-command verdict)
            (ucv-epic4-command-fingerprint verdict)
            (if (ucv-epic4-command-canonical-p verdict) "true" "false"))
    (format out "\"match\":~A},"
            (if (ucv-commands-match-p verdict) "true" "false"))
    
    ;; Artifacts
    (format out "\"artifacts\":{")
    (format out "\"epic3\":{\"valid\":~A,\"count\":~D},"
            (if (ucv-epic3-artifacts-valid-p verdict) "true" "false")
            (ucv-epic3-artifact-count verdict))
    (format out "\"epic4\":{\"valid\":~A,\"count\":~D},"
            (if (ucv-epic4-artifacts-valid-p verdict) "true" "false")
            (ucv-epic4-artifact-count verdict))
    (format out "\"total_count\":~D},"
            (ucv-total-artifact-count verdict))
    
    ;; Coverage
    (format out "\"coverage\":{")
    (format out "\"epic3\":{\"total\":~D,\"complete\":~D},"
            (ucv-epic3-scenarios-total verdict)
            (ucv-epic3-scenarios-complete verdict))
    (format out "\"epic4\":{\"total\":~D,\"complete\":~D},"
            (ucv-epic4-scenarios-total verdict)
            (ucv-epic4-scenarios-complete verdict))
    (format out "\"total_scenarios\":~D,\"passing\":~D,\"percentage\":~4,2F},"
            (ucv-total-scenarios verdict)
            (ucv-scenarios-passing verdict)
            (ucv-coverage-percentage verdict))
    
    ;; Certificate (if present)
    (write-string "\"certificate\":" out)
    (if (ucv-certificate verdict)
        (write-string (dual-framework-certificate->json (ucv-certificate verdict)) out)
        (write-string "null" out))
    
    ;; Rationale
    (write-string ",\"rationale\":[" out)
    (loop for entry in (ucv-rationale verdict)
          for i from 0 do
            (when (> i 0) (write-char #\, out))
            (write-string (%cre->json entry) out))
    
    ;; Blocking issues
    (write-string "],\"blocking_issues\":[" out)
    (loop for issue in (ucv-blocking-issues verdict)
          for i from 0 do
            (when (> i 0) (write-char #\, out))
            (format out "\"~A\"" issue))
    
    ;; Timestamps
    (write-string "],\"timestamps\":{" out)
    (format out "\"epic3\":~D,\"epic4\":~D,\"verdict\":~D}"
            (ucv-epic3-timestamp verdict)
            (ucv-epic4-timestamp verdict)
            (ucv-verdict-timestamp verdict))
    
    ;; Policy note
    (format out ",\"policy_note\":\"~A\"}" (ucv-policy-note verdict))))

;;; ── CLI Entry Point ──────────────────────────────────────────────────────────

(defun run-unified-closure-gate-compiler 
    (epic3-artifacts-dir epic3-command
     epic4-artifacts-dir epic4-command
     output-path)
  "Run unified closure gate compiler and write JSON to OUTPUT-PATH.
  
  Parameters:
    EPIC3-ARTIFACTS-DIR: Path to Epic 3 mcp-tui-driver T1-T6 artifacts
    EPIC3-COMMAND: Deterministic command for Epic 3
    EPIC4-ARTIFACTS-DIR: Path to Epic 4 Playwright S1-S6 artifacts
    EPIC4-COMMAND: Deterministic command for Epic 4
    OUTPUT-PATH: Path to write JSON verdict"
  
  (declare (type string epic3-artifacts-dir epic3-command
                   epic4-artifacts-dir epic4-command
                   output-path))
  
  (let* ((verdict (evaluate-unified-closure-gate 
                   epic3-artifacts-dir epic3-command
                   epic4-artifacts-dir epic4-command))
         (json (unified-closure-verdict->json verdict)))
    
    ;; Ensure output directory exists
    (ensure-directories-exist output-path)
    
    ;; Write JSON
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string json s))
    
    ;; Print summary
    (format t "~&Unified Closure Gate Verdict: ~A~%" (ucv-verdict verdict))
    (format t "  Pass: ~A~%" (ucv-pass-p verdict))
    (format t "  Scenarios Passing: ~D/~D (~,2F%)~%"
            (ucv-scenarios-passing verdict)
            (ucv-total-scenarios verdict)
            (ucv-coverage-percentage verdict))
    (format t "  Commands Match: ~A~%" (ucv-commands-match-p verdict))
    (format t "  Epic 3 Artifacts Valid: ~A (~D artifacts)~%"
            (ucv-epic3-artifacts-valid-p verdict)
            (ucv-epic3-artifact-count verdict))
    (format t "  Epic 4 Artifacts Valid: ~A (~D artifacts)~%"
            (ucv-epic4-artifacts-valid-p verdict)
            (ucv-epic4-artifact-count verdict))
    (format t "  Rationale Entries: ~D~%" (length (ucv-rationale verdict)))
    (format t "  Blocking Issues: ~D~%" (length (ucv-blocking-issues verdict)))
    (when (ucv-blocking-issues verdict)
      (format t "  Blocking Issues:~%")
      (dolist (issue (ucv-blocking-issues verdict))
        (format t "    - ~A~%" issue)))
    (format t "  Written to: ~A~%" output-path)
    
    ;; Return verdict for programmatic use
    verdict))
