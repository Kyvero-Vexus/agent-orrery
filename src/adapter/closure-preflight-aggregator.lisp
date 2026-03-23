;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; closure-preflight-aggregator.lisp — typed CL closure preflight aggregator
;;; Bead: agent-orrery-bv0
;;;
;;; Consumes Epic 4 S1-S6 Playwright preflight verdicts and Epic 3 T1-T6
;;; mcp-tui-driver preflight verdicts, emitting a unified machine-checkable
;;; gate decision for closure workflows.
;;;
;;; Policy:
;;;   - Epic 3 requires mcp-tui-driver for T1-T6 evidence
;;;   - Epic 4 requires Playwright for S1-S6 with screenshot+trace artifacts
;;;   - Fail-closed: any missing evidence produces :OPEN verdict

(in-package #:orrery/adapter)

;;; ---------------------------------------------------------------------------
;;; Types
;;; ---------------------------------------------------------------------------

(deftype preflight-framework ()
  '(member :playwright :mcp-tui-driver))

(deftype preflight-aggregate-verdict ()
  '(member :closed :open))

;;; ---------------------------------------------------------------------------
;;; Preflight track record (per-framework preflight state)
;;; ---------------------------------------------------------------------------

(defstruct (preflight-track-record (:conc-name ptr-)
            (:constructor make-preflight-track-record
                (&key framework pass-p command-match-p command-hash
                      required-scenarios complete-scenarios missing-scenarios detail timestamp)))
  "Single-framework preflight track for inclusion in aggregate verdict."
  (framework :playwright :type preflight-framework)
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (command-hash 0 :type integer)
  (required-scenarios 0 :type integer)
  (complete-scenarios 0 :type integer)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

;;; ---------------------------------------------------------------------------
;;; Closure preflight aggregate verdict
;;; ---------------------------------------------------------------------------

(defstruct (closure-preflight-aggregate (:conc-name cpa-)
            (:constructor make-closure-preflight-aggregate
                (&key schema-version run-id pass-p verdict epic3-track epic4-track
                 epic3-pass-p epic4-pass-p commands-match-p total-scenarios
                 total-complete total-missing blocking-issues detail timestamp)))
  "Unified machine-checkable gate decision for closure workflows.
  
  Aggregates Epic 3 mcp-tui-driver T1-T6 preflight and Epic 4 Playwright
  S1-S6 preflight into a single fail-closed verdict.
  
  Pass conditions (all required):
    - Epic 3 track: all T1-T6 scenarios complete, command matches canonical
    - Epic 4 track: all S1-S6 scenarios complete, command matches canonical
    - Commands match: both frameworks reference canonical deterministic commands
  
  Fail-closed: any missing evidence or command drift produces :OPEN verdict."
  
  ;; Identity
  (schema-version "cpa-v1" :type string)
  (run-id "" :type string)
  
  ;; Primary verdict
  (pass-p nil :type boolean)
  (verdict :open :type preflight-aggregate-verdict)
  
  ;; Per-epic tracks
  (epic3-track nil :type (or null preflight-track-record))
  (epic4-track nil :type (or null preflight-track-record))
  
  ;; Per-epic summary
  (epic3-pass-p nil :type boolean)
  (epic4-pass-p nil :type boolean)
  
  ;; Command verification
  (commands-match-p nil :type boolean)
  
  ;; Coverage metrics
  (total-scenarios 12 :type integer)
  (total-complete 0 :type integer)
  (total-missing 0 :type integer)
  
  ;; Fail-closed diagnostics
  (blocking-issues nil :type list)
  
  ;; Detail and timestamp
  (detail "" :type string)
  (timestamp 0 :type integer))

;;; ---------------------------------------------------------------------------
;;; Declarations
;;; ---------------------------------------------------------------------------

(declaim
 (ftype (function (playwright-preflight-verdict) (values preflight-track-record &optional))
        playwright-verdict->track-record)
 (ftype (function (mcp-tui-scorecard-result) (values preflight-track-record &optional))
        mcp-tui-scorecard->track-record)
 (ftype (function (preflight-track-record preflight-track-record) (values boolean &optional))
        verify-commands-match-canonical)
 (ftype (function (preflight-track-record preflight-track-record) (values list &optional))
        compute-blocking-issues)
 (ftype (function (preflight-track-record preflight-track-record)
          (values closure-preflight-aggregate &optional))
        aggregate-closure-preflight)
 (ftype (function (closure-preflight-aggregate) (values string &optional))
        closure-preflight-aggregate->json)
 (ftype (function (preflight-track-record) (values string &optional))
        track-record->json))

;;; ---------------------------------------------------------------------------
;;; Track record builders
;;; ---------------------------------------------------------------------------

(defun playwright-verdict->track-record (verdict)
  "Convert Playwright S1-S6 preflight verdict to preflight track record."
  (declare (type playwright-preflight-verdict verdict)
           (optimize (safety 3)))
  (let* ((missing (ppv-missing-scenarios verdict))
         (required (length *playwright-required-scenarios*))
         (complete (- required (length missing))))
    (make-preflight-track-record
     :framework :playwright
     :pass-p (ppv-pass-p verdict)
     :command-match-p (ppv-command-ok-p verdict)
     :command-hash (command-fingerprint *playwright-deterministic-command*)
     :required-scenarios required
     :complete-scenarios (max 0 complete)
     :missing-scenarios missing
     :detail (ppv-detail verdict)
     :timestamp (get-universal-time))))

(defun mcp-tui-scorecard->track-record (scorecard)
  "Convert mcp-tui-driver T1-T6 scorecard to preflight track record."
  (declare (type mcp-tui-scorecard-result scorecard)
           (optimize (safety 3)))
  (let* ((missing (mtsr-missing-scenarios scorecard))
         (required (length *mcp-tui-required-scenarios*))
         (complete (- required (length missing))))
    (make-preflight-track-record
     :framework :mcp-tui-driver
     :pass-p (mtsr-pass-p scorecard)
     :command-match-p (mtsr-command-match-p scorecard)
     :command-hash (mtsr-command-hash scorecard)
     :required-scenarios required
     :complete-scenarios (max 0 complete)
     :missing-scenarios missing
     :detail (mtsr-detail scorecard)
     :timestamp (get-universal-time))))

;;; ---------------------------------------------------------------------------
;;; Command verification
;;; ---------------------------------------------------------------------------

(defun verify-commands-match-canonical (epic3-track epic4-track)
  "Verify both tracks reference canonical deterministic commands.
Returns T if both commands match their respective canonical forms."
  (declare (type preflight-track-record epic3-track epic4-track)
           (optimize (safety 3)))
  (and (ptr-command-match-p epic3-track)
       (ptr-command-match-p epic4-track)))

;;; ---------------------------------------------------------------------------
;;; Blocking issue computation
;;; ---------------------------------------------------------------------------

(defun compute-blocking-issues (epic3-track epic4-track)
  "Compute list of blocking issues from preflight tracks.
Returns list of human-readable blocking issue strings."
  (declare (type preflight-track-record epic3-track epic4-track)
           (optimize (safety 3)))
  (let ((issues nil))
    ;; Epic 3 blocking issues
    (unless (ptr-pass-p epic3-track)
      (push (format nil "Epic 3 mcp-tui-driver preflight failed: ~A" (ptr-detail epic3-track))
            issues))
    (unless (ptr-command-match-p epic3-track)
      (push "Epic 3 command does not match canonical deterministic command" issues))
    (when (ptr-missing-scenarios epic3-track)
      (push (format nil "Epic 3 missing T1-T6 scenarios: ~{~A~^, ~}" 
                    (ptr-missing-scenarios epic3-track))
            issues))
    
    ;; Epic 4 blocking issues
    (unless (ptr-pass-p epic4-track)
      (push (format nil "Epic 4 Playwright preflight failed: ~A" (ptr-detail epic4-track))
            issues))
    (unless (ptr-command-match-p epic4-track)
      (push "Epic 4 command does not match canonical deterministic command" issues))
    (when (ptr-missing-scenarios epic4-track)
      (push (format nil "Epic 4 missing S1-S6 scenarios: ~{~A~^, ~}"
                    (ptr-missing-scenarios epic4-track))
            issues))
    
    (nreverse issues)))

;;; ---------------------------------------------------------------------------
;;; Core aggregator
;;; ---------------------------------------------------------------------------

(defun aggregate-closure-preflight (epic3-track epic4-track)
  "Aggregate Epic 3 and Epic 4 preflight tracks into unified closure verdict.
  
  Parameters:
    EPIC3-TRACK: Preflight track record from mcp-tui-driver T1-T6
    EPIC4-TRACK: Preflight track record from Playwright S1-S6
  
  Returns:
    CLOSURE-PREFLIGHT-AGGREGATE with unified fail-closed verdict.
  
  Pass conditions (all required):
    - Epic 3 track pass-p = T (all T1-T6 complete, command matches)
    - Epic 4 track pass-p = T (all S1-S6 complete, command matches)
    - Commands match canonical forms
  
  Fail-closed: any violation produces :OPEN verdict with blocking issues."
  
  (declare (type preflight-track-record epic3-track epic4-track)
           (optimize (safety 3)))
  
  (let* (;; Per-epic pass states
         (epic3-pass (ptr-pass-p epic3-track))
         (epic4-pass (ptr-pass-p epic4-track))
         
         ;; Command verification
         (cmds-match (verify-commands-match-canonical epic3-track epic4-track))
         
         ;; Coverage metrics
         (total-req (+ (ptr-required-scenarios epic3-track)
                       (ptr-required-scenarios epic4-track)))
         (total-complete (+ (ptr-complete-scenarios epic3-track)
                            (ptr-complete-scenarios epic4-track)))
         (total-missing (+ (length (ptr-missing-scenarios epic3-track))
                           (length (ptr-missing-scenarios epic4-track))))
         
         ;; Compute blocking issues
         (blocking (compute-blocking-issues epic3-track epic4-track))
         
         ;; Fail-closed verdict
         (pass (and epic3-pass epic4-pass cmds-match))
         (verdict (if pass :closed :open))
         
         ;; Detail message
         (detail (if pass
                     "Closure preflight aggregate PASSED: Epic 3 T1-T6 and Epic 4 S1-S6 complete with canonical commands."
                     (format nil "Closure preflight aggregate FAILED: ~D blocking issue~:P"
                             (length blocking)))))
    
    (make-closure-preflight-aggregate
     :schema-version "cpa-v1"
     :run-id (format nil "cpa-~D" (get-universal-time))
     :pass-p pass
     :verdict verdict
     :epic3-track epic3-track
     :epic4-track epic4-track
     :epic3-pass-p epic3-pass
     :epic4-pass-p epic4-pass
     :commands-match-p cmds-match
     :total-scenarios total-req
     :total-complete total-complete
     :total-missing total-missing
     :blocking-issues blocking
     :detail detail
     :timestamp (get-universal-time))))

;;; ---------------------------------------------------------------------------
;;; Convenience function: aggregate from raw verdicts
;;; ---------------------------------------------------------------------------

(defun aggregate-from-raw-verdicts (playwright-verdict mcp-tui-scorecard)
  "Aggregate from raw preflight verdicts.
  
  Parameters:
    PLAYWRIGHT-VERDICT: playwright-preflight-verdict from Epic 4 S1-S6
    MCP-TUI-SCORECARD: mcp-tui-scorecard-result from Epic 3 T1-T6
  
  Returns:
    CLOSURE-PREFLIGHT-AGGREGATE with unified verdict."
  
  (declare (type playwright-preflight-verdict playwright-verdict)
           (type mcp-tui-scorecard-result mcp-tui-scorecard)
           (optimize (safety 3)))
  
  (let ((epic3-track (mcp-tui-scorecard->track-record mcp-tui-scorecard))
        (epic4-track (playwright-verdict->track-record playwright-verdict)))
    (aggregate-closure-preflight epic3-track epic4-track)))

;;; ---------------------------------------------------------------------------
;;; Convenience function: run aggregation from artifact directories
;;; ---------------------------------------------------------------------------

(defun run-closure-preflight-aggregator (playwright-artifacts-dir playwright-command
                                          mcp-tui-artifacts-dir mcp-tui-command)
  "Run full closure preflight aggregation from artifact directories.
  
  Parameters:
    PLAYWRIGHT-ARTIFACTS-DIR: Path to Epic 4 Playwright S1-S6 artifacts
    PLAYWRIGHT-COMMAND: Deterministic command for Playwright
    MCP-TUI-ARTIFACTS-DIR: Path to Epic 3 mcp-tui-driver T1-T6 artifacts
    MCP-TUI-COMMAND: Deterministic command for mcp-tui-driver
  
  Returns:
    CLOSURE-PREFLIGHT-AGGREGATE with unified verdict."
  
  (declare (type string playwright-artifacts-dir playwright-command
                   mcp-tui-artifacts-dir mcp-tui-command)
           (optimize (safety 3)))
  
  (let* ((playwright-verdict (run-playwright-s1-s6-preflight 
                              playwright-artifacts-dir playwright-command))
         (mcp-tui-scorecard (evaluate-mcp-tui-scorecard-gate
                             mcp-tui-artifacts-dir mcp-tui-command)))
    (aggregate-from-raw-verdicts playwright-verdict mcp-tui-scorecard)))

;;; ---------------------------------------------------------------------------
;;; JSON serialization
;;; ---------------------------------------------------------------------------

(defun track-record->json (track)
  "Serialize PREFLIGHT-TRACK-RECORD to JSON string."
  (declare (type preflight-track-record track))
  (with-output-to-string (s)
    (format s "{\"framework\":\"~A\",\"pass\":~A,\"command_match\":~A,\"command_hash\":~D,"
            (ptr-framework track)
            (if (ptr-pass-p track) "true" "false")
            (if (ptr-command-match-p track) "true" "false")
            (ptr-command-hash track))
    (format s "\"required\":~D,\"complete\":~D,\"missing_count\":~D,"
            (ptr-required-scenarios track)
            (ptr-complete-scenarios track)
            (length (ptr-missing-scenarios track)))
    (write-string "\"missing\":[" s)
    (loop for sid in (ptr-missing-scenarios track)
          for i from 0 do
            (when (> i 0) (write-char #\, s))
            (format s "\"~A\"" (json-escape-string sid)))
    (format s "],\"detail\":\"~A\",\"timestamp\":~D}"
            (json-escape-string (ptr-detail track))
            (ptr-timestamp track))))

(defun closure-preflight-aggregate->json (aggregate)
  "Serialize CLOSURE-PREFLIGHT-AGGREGATE to deterministic JSON string.
  
  Produces machine-checkable JSON with stable field ordering."
  (declare (type closure-preflight-aggregate aggregate)
           (optimize (safety 3)))
  (with-output-to-string (out)
    ;; Header
    (format out "{\"schema\":\"~A\",\"run_id\":\"~A\","
            (cpa-schema-version aggregate)
            (cpa-run-id aggregate))
    
    ;; Primary verdict
    (format out "\"pass\":~A,\"verdict\":\"~(~A~)\","
            (if (cpa-pass-p aggregate) "true" "false")
            (cpa-verdict aggregate))
    
    ;; Per-epic summary
    (format out "\"epic3_pass\":~A,\"epic4_pass\":~A,"
            (if (cpa-epic3-pass-p aggregate) "true" "false")
            (if (cpa-epic4-pass-p aggregate) "true" "false"))
    
    ;; Command verification
    (format out "\"commands_match\":~A,"
            (if (cpa-commands-match-p aggregate) "true" "false"))
    
    ;; Coverage metrics
    (format out "\"coverage\":{\"total\":~D,\"complete\":~D,\"missing\":~D},"
            (cpa-total-scenarios aggregate)
            (cpa-total-complete aggregate)
            (cpa-total-missing aggregate))
    
    ;; Epic 3 track
    (write-string "\"epic3_track\":" out)
    (if (cpa-epic3-track aggregate)
        (write-string (track-record->json (cpa-epic3-track aggregate)) out)
        (write-string "null" out))
    
    ;; Epic 4 track
    (write-string ",\"epic4_track\":" out)
    (if (cpa-epic4-track aggregate)
        (write-string (track-record->json (cpa-epic4-track aggregate)) out)
        (write-string "null" out))
    
    ;; Blocking issues
    (write-string ",\"blocking_issues\":[" out)
    (loop for issue in (cpa-blocking-issues aggregate)
          for i from 0 do
            (when (> i 0) (write-char #\, out))
            (format out "\"~A\"" (json-escape-string issue)))
    
    ;; Detail and timestamp
    (format out "],\"detail\":\"~A\",\"timestamp\":~D}"
            (json-escape-string (cpa-detail aggregate))
            (cpa-timestamp aggregate))))

;;; ---------------------------------------------------------------------------
;;; Helper functions
;;; ---------------------------------------------------------------------------

(defun json-escape-string (input)
  "Escape string for JSON output."
  (declare (type string input))
  (with-output-to-string (out)
    (loop for ch across input
          do (case ch
               (#\\ (write-string "\\\\" out))
               (#\" (write-string "\\\"" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (t (write-char ch out))))))
