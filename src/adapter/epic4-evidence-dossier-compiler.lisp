;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic4-evidence-dossier-compiler.lisp — typed S1-S6 evidence dossier compiler
;;; Bead: agent-orrery-nlup
;;;
;;; Ingests Playwright S1-S6 closure attestations and emits deterministic,
;;; machine-checkable evidence dossiers for web lineage beads (eb0.4.5).
;;; Fail-closed: any missing artifact or command drift produces :OPEN verdict.

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype dossier-verdict ()
  '(member :closed :open))

(deftype dossier-diagnostic-category ()
  '(member :pass :missing-screenshot :missing-trace :command-drift :digest-error :incomplete))

(defstruct (epic4-dossier-diagnostic (:conc-name edd-))
  "Single fail-closed diagnostic for Epic 4 dossier."
  (scenario-id "" :type string)
  (category :pass :type dossier-diagnostic-category)
  (expected-screenshot "" :type string)
  (expected-trace "" :type string)
  (actual-screenshot-digest "" :type string)
  (actual-trace-digest "" :type string)
  (detail "" :type string))

(defstruct (epic4-scenario-record (:conc-name e4sr-))
  "Per-scenario evidence record for S1-S6."
  (scenario-id "" :type string)
  (command-fingerprint 0 :type integer)
  (screenshot-digest "" :type string)
  (trace-digest "" :type string)
  (transcript-hash 0 :type integer)
  (evidence-complete-p nil :type boolean)
  (verdict :missing :type (member :pass :fail :missing)))

(defstruct (epic4-evidence-dossier (:conc-name e4ed-))
  "Machine-checkable evidence dossier for Epic 4 S1-S6 web lineage beads."
  (run-id "" :type string)
  (lineage-tag "eb0.4.5" :type string)
  (deterministic-command "" :type string)
  (command-fingerprint 0 :type integer)
  (scenario-coverage 0.0 :type single-float)
  (records nil :type list)                      ; list of epic4-scenario-record
  (screenshot-digests nil :type list)           ; alist: (scenario-id . digest)
  (trace-digests nil :type list)                ; alist: (scenario-id . digest)
  (transcript-attestations nil :type list)      ; alist: (scenario-id . hash)
  (fail-closed-diagnostics nil :type list)      ; list of epic4-dossier-diagnostic
  (closure-verdict :open :type dossier-verdict)
  (timestamp 0 :type integer)
  (policy-note "Epic 4 MUST NOT be reported closed without Playwright-backed S1-S6 screenshot+trace evidence." :type string))

;;; ── Declaims ─────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (epic4-scenario-attestation) (values epic4-scenario-record &optional))
        attestation->scenario-record)
 (ftype (function (epic4-scenario-attestation epic4-scenario-record)
          (values epic4-dossier-diagnostic &optional))
        build-scenario-diagnostic)
 (ftype (function (epic4-closure-attestation) (values epic4-evidence-dossier &optional))
        compile-epic4-evidence-dossier)
 (ftype (function (epic4-evidence-dossier) (values string &optional))
        epic4-evidence-dossier->json))

;;; ── Scenario record compiler ─────────────────────────────────────────────────

(defun attestation->scenario-record (attestation)
  "Convert a single scenario attestation to a dossier scenario record."
  (declare (type epic4-scenario-attestation attestation)
           (optimize (safety 3)))
  (let* ((scr-ok (e4sa-screenshot-present-p attestation))
         (trc-ok (e4sa-trace-present-p attestation))
         (complete-p (and scr-ok trc-ok))
         (verdict (cond
                    (complete-p :pass)
                    ((or scr-ok trc-ok) :fail)
                    (t :missing))))
    (make-epic4-scenario-record
     :scenario-id (e4sa-scenario-id attestation)
     :command-fingerprint (e4sa-command-fingerprint attestation)
     :screenshot-digest (e4sa-screenshot-digest attestation)
     :trace-digest (e4sa-trace-digest attestation)
     :transcript-hash (e4sa-transcript-fingerprint attestation)
     :evidence-complete-p complete-p
     :verdict verdict)))

;;; ── Diagnostic builder ───────────────────────────────────────────────────────

(defun build-scenario-diagnostic (attestation record)
  "Build fail-closed diagnostic for one scenario based on attestation and record state."
  (declare (type epic4-scenario-attestation attestation)
           (type epic4-scenario-record record)
           (optimize (safety 3)))
  (let* ((sid (e4sr-scenario-id record))
         (scr-ok (e4sa-screenshot-present-p attestation))
         (trc-ok (e4sa-trace-present-p attestation))
         (cmd-ok (= (e4sa-command-fingerprint attestation) *playwright-canonical-command-hash*)))
    (cond
      ;; All checks pass
      ((and scr-ok trc-ok cmd-ok)
       (make-epic4-dossier-diagnostic
        :scenario-id sid
        :category :pass
        :expected-screenshot (e4sa-screenshot-path attestation)
        :expected-trace (e4sa-trace-path attestation)
        :actual-screenshot-digest (e4sr-screenshot-digest record)
        :actual-trace-digest (e4sr-trace-digest record)
        :detail (format nil "~A: evidence complete" sid)))
      
      ;; Missing screenshot
      ((not scr-ok)
       (make-epic4-dossier-diagnostic
        :scenario-id sid
        :category :missing-screenshot
        :expected-screenshot (format nil "e2e/screenshots/~A.png" sid)
        :expected-trace ""
        :actual-screenshot-digest ""
        :actual-trace-digest ""
        :detail (format nil "~A: missing screenshot artifact" sid)))
      
      ;; Missing trace
      ((not trc-ok)
       (make-epic4-dossier-diagnostic
        :scenario-id sid
        :category :missing-trace
        :expected-screenshot ""
        :expected-trace (format nil "e2e/traces/~A.zip" sid)
        :actual-screenshot-digest (e4sr-screenshot-digest record)
        :actual-trace-digest ""
        :detail (format nil "~A: missing trace artifact" sid)))
      
      ;; Command drift
      ((not cmd-ok)
       (make-epic4-dossier-diagnostic
        :scenario-id sid
        :category :command-drift
        :expected-screenshot ""
        :expected-trace ""
        :actual-screenshot-digest ""
        :actual-trace-digest ""
        :detail (format nil "~A: command fingerprint drift detected" sid)))
      
      ;; Generic incomplete
      (t
       (make-epic4-dossier-diagnostic
        :scenario-id sid
        :category :incomplete
        :expected-screenshot ""
        :expected-trace ""
        :actual-screenshot-digest ""
        :actual-trace-digest ""
        :detail (format nil "~A: evidence incomplete" sid))))))

;;; ── Core dossier compiler ────────────────────────────────────────────────────

(defun compile-epic4-evidence-dossier (attestation)
  "Compile evidence dossier from Epic 4 S1-S6 closure attestation.
Returns an EPIC4-EVIDENCE-DOSSIER with deterministic JSON shape."
  (declare (type epic4-closure-attestation attestation)
           (optimize (safety 3)))
  (let* ((records (mapcar #'attestation->scenario-record (e4ca-attestations attestation)))
         (all-complete-p (every #'e4sr-evidence-complete-p records))
         (cmd-match-p (= (e4ca-command-fingerprint attestation) *playwright-canonical-command-hash*))
         (attestation-closed-p (eq (e4ca-closure-verdict attestation) :closed))
         (complete-p (and all-complete-p cmd-match-p attestation-closed-p))
         (coverage (/ (count-if #'e4sr-evidence-complete-p records) 6.0))
         (diagnostics nil)
         (scr-digests nil)
         (trc-digests nil)
         (tx-attestations nil))
    
    ;; Build diagnostics for each scenario
    (loop for att in (e4ca-attestations attestation)
          for rec in records
          do (push (build-scenario-diagnostic att rec) diagnostics))
    
    ;; Build screenshot digest map
    (dolist (rec records)
      (push (cons (e4sr-scenario-id rec) (e4sr-screenshot-digest rec)) scr-digests))
    
    ;; Build trace digest map
    (dolist (rec records)
      (push (cons (e4sr-scenario-id rec) (e4sr-trace-digest rec)) trc-digests))
    
    ;; Build transcript attestation map
    (dolist (rec records)
      (push (cons (e4sr-scenario-id rec) (e4sr-transcript-hash rec)) tx-attestations))
    
    ;; Final verdict: fail-closed unless all evidence present and canonical
    (let ((closure-verdict (if complete-p :closed :open)))
      (make-epic4-evidence-dossier
       :run-id (format nil "epic4-dossier-~D" (get-universal-time))
       :lineage-tag (e4ca-lineage-tag attestation)
       :deterministic-command (e4ca-deterministic-command attestation)
       :command-fingerprint (e4ca-command-fingerprint attestation)
       :scenario-coverage coverage
       :records (nreverse records)
       :screenshot-digests (nreverse scr-digests)
       :trace-digests (nreverse trc-digests)
       :transcript-attestations (nreverse tx-attestations)
       :fail-closed-diagnostics (nreverse diagnostics)
       :closure-verdict closure-verdict
       :timestamp (get-universal-time)))))

;;; ── JSON serialization ───────────────────────────────────────────────────────

(defun %scenario-record->json (r)
  "Serialize EPIC4-SCENARIO-RECORD to JSON string."
  (declare (type epic4-scenario-record r))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"cmd_fp\":~D,\"scr_digest\":\"~A\",\"trc_digest\":\"~A\",\"tx_hash\":~D,\"complete\":~A,\"verdict\":\"~(~A~)\"}"
            (e4sr-scenario-id r)
            (e4sr-command-fingerprint r)
            (e4sr-screenshot-digest r)
            (e4sr-trace-digest r)
            (e4sr-transcript-hash r)
            (if (e4sr-evidence-complete-p r) "true" "false")
            (e4sr-verdict r))))

(defun %dossier-diagnostic->json (d)
  "Serialize EPIC4-DOSSIER-DIAGNOSTIC to JSON string."
  (declare (type epic4-dossier-diagnostic d))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"category\":\"~(~A~)\",\"expected_scr\":\"~A\",\"expected_trc\":\"~A\",\"actual_scr_digest\":\"~A\",\"actual_trc_digest\":\"~A\",\"detail\":\"~A\"}"
            (edd-scenario-id d)
            (edd-category d)
            (edd-expected-screenshot d)
            (edd-expected-trace d)
            (edd-actual-screenshot-digest d)
            (edd-actual-trace-digest d)
            (edd-detail d))))

(defun epic4-evidence-dossier->json (dossier)
  "Serialize EPIC4-EVIDENCE-DOSSIER to deterministic JSON."
  (declare (type epic4-evidence-dossier dossier))
  (with-output-to-string (out)
    (format out "{\"run_id\":\"~A\",\"lineage\":\"~A\",\"command\":\"~A\",\"cmd_fp\":~D,\"coverage\":~4,2F,\"verdict\":\"~(~A~)\",\"timestamp\":~D,"
            (e4ed-run-id dossier)
            (e4ed-lineage-tag dossier)
            (e4ed-deterministic-command dossier)
            (e4ed-command-fingerprint dossier)
            (e4ed-scenario-coverage dossier)
            (e4ed-closure-verdict dossier)
            (e4ed-timestamp dossier))
    
    ;; Scenario records
    (write-string "\"records\":[" out)
    (loop for r in (e4ed-records dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%scenario-record->json r) out)))
    
    ;; Screenshot digests
    (write-string "],\"screenshot_digests\":{" out)
    (loop for (sid . digest) in (e4ed-screenshot-digests dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\":\"~A\"" sid digest)))
    
    ;; Trace digests
    (write-string "},\"trace_digests\":{" out)
    (loop for (sid . digest) in (e4ed-trace-digests dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\":\"~A\"" sid digest)))
    
    ;; Transcript attestations
    (write-string "},\"tx_attestations\":{" out)
    (loop for (sid . hash) in (e4ed-transcript-attestations dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\":~D" sid hash)))
    
    ;; Diagnostics
    (write-string "},\"diagnostics\":[" out)
    (loop for d in (e4ed-fail-closed-diagnostics dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%dossier-diagnostic->json d) out)))
    
    ;; Policy note
    (format out "],\"policy_note\":\"~A\"}" (e4ed-policy-note dossier))))

;;; ── CLI entry point ──────────────────────────────────────────────────────────

(defun run-epic4-evidence-dossier-compiler (attestation-path output-path)
  "Run the evidence dossier compiler on an attestation file and write JSON to OUTPUT-PATH.
ATTESTATION-PATH should contain a JSON-serialized epic4-closure-attestation."
  (declare (type string attestation-path output-path))
  ;; For now, bootstrap from replay table + merger report (same as exporter CLI)
  ;; In production, this would deserialize the attestation from JSON
  (let* ((artifact-root (directory-namestring attestation-path))
         (replay-table (compile-playwright-replay-table artifact-root *playwright-canonical-command*))
         (merger-report (merge-playwright-attestations->envelope nil))
         (attestation (compile-epic4-closure-attestation replay-table merger-report))
         (dossier (compile-epic4-evidence-dossier attestation))
         (json (epic4-evidence-dossier->json dossier)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string json s))
    (format t "~&Epic 4 Evidence Dossier: ~A~%" (e4ed-closure-verdict dossier))
    (format t "  Lineage: ~A~%" (e4ed-lineage-tag dossier))
    (format t "  Coverage: ~4,2F%~%" (* 100 (e4ed-scenario-coverage dossier)))
    (format t "  Records: ~D~%" (length (e4ed-records dossier)))
    (format t "  Diagnostics: ~D~%" (length (e4ed-fail-closed-diagnostics dossier)))
    (format t "  Written to: ~A~%" output-path)
    dossier))
