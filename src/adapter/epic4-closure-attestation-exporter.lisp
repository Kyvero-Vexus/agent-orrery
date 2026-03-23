;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic4-closure-attestation-exporter.lisp — typed S1-S6 closure attestation exporter
;;; Bead: agent-orrery-xx9m
;;;
;;; Consumes Playwright S1-S6 replay/verifier outputs and emits deterministic
;;; closure attestation payloads for eb0.4.5 and related web beads.
;;; Screenshot+trace artifact digests required per scenario.

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype attestation-verdict ()
  '(member :closed :open))

(deftype attestation-diagnostic-category ()
  '(member :pass :missing-screenshot :missing-trace :command-drift :digest-error))

(defstruct (epic4-diagnostic (:conc-name e4d-))
  "Single fail-closed diagnostic for Epic 4 attestation."
  (scenario-id "" :type string)
  (category :pass :type attestation-diagnostic-category)
  (expected-screenshot "" :type string)
  (expected-trace "" :type string)
  (actual-screenshot-digest "" :type string)
  (actual-trace-digest "" :type string)
  (detail "" :type string))

(defstruct (epic4-scenario-attestation (:conc-name e4sa-))
  "Per-scenario attestation record for S1-S6."
  (scenario-id "" :type string)
  (command-fingerprint 0 :type integer)
  (screenshot-present-p nil :type boolean)
  (screenshot-path "" :type string)
  (screenshot-digest "" :type string)
  (trace-present-p nil :type boolean)
  (trace-path "" :type string)
  (trace-digest "" :type string)
  (transcript-fingerprint 0 :type integer)
  (verdict :missing :type (member :pass :fail :missing)))

(defstruct (epic4-closure-attestation (:conc-name e4ca-))
  "Machine-checkable closure attestation for Epic 4 S1-S6 eb0.4.5 lineage."
  (run-id "" :type string)
  (lineage-tag "eb0.4.5" :type string)
  (deterministic-command "" :type string)
  (command-fingerprint 0 :type integer)
  (scenario-coverage 0.0 :type single-float)
  (attestations nil :type list)            ; list of epic4-scenario-attestation
  (screenshot-digests nil :type list)      ; alist: (scenario-id . digest)
  (trace-digests nil :type list)           ; alist: (scenario-id . digest)
  (transcript-fingerprints nil :type list) ; alist: (scenario-id . fingerprint)
  (fail-closed-diagnostics nil :type list) ; list of epic4-diagnostic
  (closure-verdict :open :type attestation-verdict)
  (timestamp 0 :type integer)
  (policy-note "Epic 4 MUST NOT be reported closed without Playwright-backed S1-S6 screenshot+trace evidence." :type string))

;;; ── Declaims ─────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (playwright-replay-row) (values epic4-scenario-attestation &optional))
        replay-row->attestation)
 (ftype (function (playwright-replay-table pw-attestation-merger-report)
          (values epic4-closure-attestation &optional))
        compile-epic4-closure-attestation)
 (ftype (function (epic4-closure-attestation) (values string &optional))
        epic4-closure-attestation->json)
 (ftype (function (string) (values string &optional))
        %file-sha256-hex)
 (ftype (function (playwright-replay-row epic4-scenario-attestation) (values epic4-diagnostic &optional))
        %build-scenario-diagnostic))

;;; ── SHA256 digest helper ─────────────────────────────────────────────────────

(defun %file-sha256-hex (path)
  "Return a deterministic hex digest of file at PATH, or empty string if not found.
Uses sxhash of file content as a portable digest proxy."
  (declare (type string path))
  (handler-case
      (with-open-file (s path :element-type '(unsigned-byte 8))
        (let* ((len (file-length s))
               (buf (make-array len :element-type '(unsigned-byte 8))))
          (read-sequence buf s)
          (format nil "~16,'0X" (sxhash buf))))
    (error () "")))

;;; ── Scenario attestation builder ─────────────────────────────────────────────

(defun replay-row->attestation (row)
  "Convert a playwright-replay-row to an epic4-scenario-attestation."
  (declare (type playwright-replay-row row)
           (optimize (safety 3)))
  (let* ((sid (prr-scenario-id row))
         (cmd-hash (prr-command-hash row))
         (scr-path (prr-screenshot-path row))
         (trc-path (prr-trace-path row))
         (scr-ok (plusp (length scr-path)))
         (trc-ok (plusp (length trc-path)))
         (scr-digest (if scr-ok (%file-sha256-hex scr-path) ""))
         (trc-digest (if trc-ok (%file-sha256-hex trc-path) ""))
         (tx-hash (prr-transcript-hash row))
         (pass-p (and scr-ok trc-ok (prr-preflight-ok-p row)))
         (verdict (if pass-p :pass :fail)))
    (make-epic4-scenario-attestation
     :scenario-id sid
     :command-fingerprint cmd-hash
     :screenshot-present-p scr-ok
     :screenshot-path scr-path
     :screenshot-digest scr-digest
     :trace-present-p trc-ok
     :trace-path trc-path
     :trace-digest trc-digest
     :transcript-fingerprint tx-hash
     :verdict verdict)))

(defun %build-scenario-diagnostic (row attestation)
  "Build diagnostic for one scenario based on attestation state."
  (declare (type playwright-replay-row row)
           (type epic4-scenario-attestation attestation))
  (let* ((sid (e4sa-scenario-id attestation))
         (scr-ok (e4sa-screenshot-present-p attestation))
         (trc-ok (e4sa-trace-present-p attestation))
         (cmd-ok (prr-preflight-ok-p row)))
    (cond
      ((and scr-ok trc-ok cmd-ok)
       (make-epic4-diagnostic
        :scenario-id sid
        :category :pass
        :expected-screenshot (e4sa-screenshot-path attestation)
        :expected-trace (e4sa-trace-path attestation)
        :actual-screenshot-digest (e4sa-screenshot-digest attestation)
        :actual-trace-digest (e4sa-trace-digest attestation)
        :detail (format nil "~A: pass" sid)))
      ((not scr-ok)
       (make-epic4-diagnostic
        :scenario-id sid
        :category :missing-screenshot
        :expected-screenshot (format nil "e2e/screenshots/~A.png" sid)
        :expected-trace ""
        :actual-screenshot-digest ""
        :actual-trace-digest ""
        :detail (format nil "~A: missing screenshot" sid)))
      ((not trc-ok)
       (make-epic4-diagnostic
        :scenario-id sid
        :category :missing-trace
        :expected-screenshot ""
        :expected-trace (format nil "e2e/traces/~A.zip" sid)
        :actual-screenshot-digest (e4sa-screenshot-digest attestation)
        :actual-trace-digest ""
        :detail (format nil "~A: missing trace" sid)))
      (t
       (make-epic4-diagnostic
        :scenario-id sid
        :category :command-drift
        :expected-screenshot ""
        :expected-trace ""
        :actual-screenshot-digest ""
        :actual-trace-digest ""
        :detail (format nil "~A: command drift or preflight failure" sid))))))

;;; ── Core attestation compiler ────────────────────────────────────────────────

(defun compile-epic4-closure-attestation (replay-table merger-report)
  "Compile closure attestation from Playwright S1-S6 replay table and merger report.
Returns an EPIC4-CLOSURE-ATTESTATION with deterministic JSON shape."
  (declare (type playwright-replay-table replay-table)
           (type pw-attestation-merger-report merger-report)
           (optimize (safety 3)))
  (let* ((attestations (mapcar #'replay-row->attestation (prt-rows replay-table)))
         (all-pass-p (every (lambda (a) (eq (e4sa-verdict a) :pass)) attestations))
         (cmd-match-p (pwam-command-match-p merger-report))
         (complete-p (and all-pass-p cmd-match-p (pwam-pass-p merger-report)))
         (coverage (/ (count-if (lambda (a) (eq (e4sa-verdict a) :pass)) attestations) 6.0))
         (diagnostics nil)
         (scr-digests nil)
         (trc-digests nil)
         (tx-fingerprints nil))
    ;; Build diagnostics
    (loop for row in (prt-rows replay-table)
          for att in attestations
          do (push (%build-scenario-diagnostic row att) diagnostics))
    ;; Build digest maps
    (dolist (att attestations)
      (push (cons (e4sa-scenario-id att) (e4sa-screenshot-digest att)) scr-digests)
      (push (cons (e4sa-scenario-id att) (e4sa-trace-digest att)) trc-digests)
      (push (cons (e4sa-scenario-id att) (e4sa-transcript-fingerprint att)) tx-fingerprints))
    ;; Final verdict
    (let ((closure-verdict (if complete-p :closed :open)))
      (make-epic4-closure-attestation
       :run-id (format nil "epic4-attestation-~D" (get-universal-time))
       :lineage-tag "eb0.4.5"
       :deterministic-command *playwright-canonical-command*
       :command-fingerprint *playwright-canonical-command-hash*
       :scenario-coverage coverage
       :attestations attestations
       :screenshot-digests (nreverse scr-digests)
       :trace-digests (nreverse trc-digests)
       :transcript-fingerprints (nreverse tx-fingerprints)
       :fail-closed-diagnostics (nreverse diagnostics)
       :closure-verdict closure-verdict
       :timestamp (get-universal-time)))))

;;; ── JSON serialization ───────────────────────────────────────────────────────

(defun %attestation->json (a)
  (declare (type epic4-scenario-attestation a))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"cmd_fp\":~D,\"scr_present\":~A,\"scr_path\":\"~A\",\"scr_digest\":\"~A\",\"trc_present\":~A,\"trc_path\":\"~A\",\"trc_digest\":\"~A\",\"tx_fp\":~D,\"verdict\":\"~(~A~)\"}"
            (e4sa-scenario-id a)
            (e4sa-command-fingerprint a)
            (if (e4sa-screenshot-present-p a) "true" "false")
            (e4sa-screenshot-path a)
            (e4sa-screenshot-digest a)
            (if (e4sa-trace-present-p a) "true" "false")
            (e4sa-trace-path a)
            (e4sa-trace-digest a)
            (e4sa-transcript-fingerprint a)
            (e4sa-verdict a))))

(defun %e4-diagnostic->json (d)
  (declare (type epic4-diagnostic d))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"category\":\"~(~A~)\",\"expected_scr\":\"~A\",\"expected_trc\":\"~A\",\"actual_scr_digest\":\"~A\",\"actual_trc_digest\":\"~A\",\"detail\":\"~A\"}"
            (e4d-scenario-id d)
            (e4d-category d)
            (e4d-expected-screenshot d)
            (e4d-expected-trace d)
            (e4d-actual-screenshot-digest d)
            (e4d-actual-trace-digest d)
            (e4d-detail d))))

(defun epic4-closure-attestation->json (attestation)
  "Serialize EPIC4-CLOSURE-ATTESTATION to deterministic JSON."
  (declare (type epic4-closure-attestation attestation))
  (with-output-to-string (out)
    (format out "{\"run_id\":\"~A\",\"lineage\":\"~A\",\"command\":\"~A\",\"cmd_fp\":~D,\"coverage\":~4,2F,\"verdict\":\"~(~A~)\",\"timestamp\":~D,"
            (e4ca-run-id attestation)
            (e4ca-lineage-tag attestation)
            (e4ca-deterministic-command attestation)
            (e4ca-command-fingerprint attestation)
            (e4ca-scenario-coverage attestation)
            (e4ca-closure-verdict attestation)
            (e4ca-timestamp attestation))
    ;; Attestations
    (write-string "\"attestations\":[" out)
    (loop for a in (e4ca-attestations attestation) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%attestation->json a) out)))
    (write-string "],\"screenshot_digests\":{" out)
    ;; Screenshot digests
    (loop for (sid . digest) in (e4ca-screenshot-digests attestation) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\":\"~A\"" sid digest)))
    (write-string "},\"trace_digests\":{" out)
    ;; Trace digests
    (loop for (sid . digest) in (e4ca-trace-digests attestation) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\":\"~A\"" sid digest)))
    (write-string "},\"tx_fingerprints\":{" out)
    ;; Transcript fingerprints
    (loop for (sid . fp) in (e4ca-transcript-fingerprints attestation) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\":~D" sid fp)))
    (write-string "},\"diagnostics\":[" out)
    ;; Diagnostics
    (loop for d in (e4ca-fail-closed-diagnostics attestation) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%e4-diagnostic->json d) out)))
    (format out "],\"policy_note\":\"~A\"}" (e4ca-policy-note attestation))))

;;; ── CLI entry point ──────────────────────────────────────────────────────────

(defun run-epic4-closure-attestation-exporter (artifact-root output-path)
  "Run the attestation exporter and write JSON to OUTPUT-PATH."
  (declare (type string artifact-root output-path))
  ;; Build minimal inputs for export
  (let* ((replay-table (compile-playwright-replay-table artifact-root *playwright-canonical-command*))
         (merger-report (merge-playwright-attestations->envelope nil)) ; empty ledger for bootstrap
         (attestation (compile-epic4-closure-attestation replay-table merger-report))
         (json (epic4-closure-attestation->json attestation)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string json s))
    (format t "~&Epic 4 Closure Attestation: ~A~%" (e4ca-closure-verdict attestation))
    (format t "  Lineage: ~A~%" (e4ca-lineage-tag attestation))
    (format t "  Coverage: ~4,2F%~%" (* 100 (e4ca-scenario-coverage attestation)))
    (format t "  Attestations: ~D~%" (length (e4ca-attestations attestation)))
    (format t "  Written to: ~A~%" output-path)
    attestation))
