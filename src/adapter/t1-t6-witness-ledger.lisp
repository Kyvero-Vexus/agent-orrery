;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-witness-ledger.lisp — typed T1-T6 artifact witness ledger + lockfile emitter
;;; Bead: agent-orrery-om6o
;;;
;;; Converts mcp-tui-driver T1-T6 contract-matrix output into immutable lockfile
;;; records. Fail-closed: any missing artifact yields a non-closable verdict.
;;;
;;; Deterministic command: cd e2e-tui && ./run-tui-e2e-t1-t6.sh

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(defstruct (t1-t6-lock-record (:conc-name tlr-))
  "Immutable lockfile record for one T1-T6 scenario."
  (scenario-id          ""  :type string)
  (deterministic-command ""  :type string)
  (command-fingerprint  0   :type integer)
  (artifact-root        ""  :type string)
  (artifact-pointers    nil :type list)   ; list of strings (relative paths)
  (transcript-digest    0   :type integer)
  (all-artifacts-present-p nil :type boolean)
  (missing-artifacts    nil :type list)   ; list of strings
  (detail               ""  :type string))

(defstruct (t1-t6-witness-ledger (:conc-name twl-))
  "Immutable witness ledger for all T1-T6 scenarios."
  (run-id               ""  :type string)
  (deterministic-command ""  :type string)
  (command-fingerprint  0   :type integer)
  (records              nil :type list)   ; list of t1-t6-lock-record
  (all-present-p        nil :type boolean)
  (missing-count        0   :type integer)
  (closure-verdict      :open :type symbol) ; :CLOSED | :OPEN
  (timestamp            0   :type integer)
  (detail               ""  :type string))

;;; ── Declaims ─────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (tui-contract-row string) (values t1-t6-lock-record &optional))
        contract-row->lock-record)
 (ftype (function (tui-contract-matrix string) (values t1-t6-witness-ledger &optional))
        compile-t1-t6-witness-ledger)
 (ftype (function (t1-t6-witness-ledger) (values string &optional))
        t1-t6-witness-ledger->json))

;;; ── Constants ────────────────────────────────────────────────────────────────

(defparameter *tui-deterministic-command*
  "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
  "Canonical deterministic command for T1-T6 mcp-tui-driver runs.")

(defparameter *tui-required-artifact-kinds-ledger*
  '("transcript" "screenshot" "asciicast" "report")
  "Artifact kinds required for each T1-T6 scenario in the witness ledger.")

;;; ── Implementation ───────────────────────────────────────────────────────────

(defun %scenario-artifact-path (scenario-id kind artifact-root)
  "Return expected path for one T1-T6 scenario artifact."
  (declare (type string scenario-id kind artifact-root))
  (format nil "~A~A-~A~A"
          artifact-root
          scenario-id
          kind
          (cond ((string= kind "screenshot") ".png")
                ((string= kind "asciicast")  ".cast")
                ((string= kind "report")     ".json")
                (t                           ".txt"))))

(defun %probe-artifacts (scenario-id artifact-root)
  "Return (pointers missing) for all required artifact kinds."
  (declare (type string scenario-id artifact-root))
  (let ((pointers nil)
        (missing  nil))
    (dolist (kind *tui-required-artifact-kinds-ledger*)
      (let ((path (%scenario-artifact-path scenario-id kind artifact-root)))
        (if (probe-file path)
            (push path pointers)
            (push (format nil "~A/~A-~A" artifact-root scenario-id kind) missing))))
    (values (nreverse pointers) (nreverse missing))))

(defun contract-row->lock-record (row artifact-root)
  "Convert a tui-contract-row to an immutable t1-t6-lock-record."
  (declare (type tui-contract-row row)
           (type string artifact-root)
           (optimize (safety 3)))
  (let* ((scenario-id (tcr-scenario-id row))
         (cmd         (tcr-command row))
         (cmd-fp      (tcr-command-hash row))
         (tx-digest   (tcr-transcript-hash row)))
    (multiple-value-bind (pointers missing)
        (%probe-artifacts scenario-id artifact-root)
      (let* ((all-present (null missing))
             (detail      (if all-present
                              (format nil "~A: all artifacts present (~D)"
                                      scenario-id (length pointers))
                              (format nil "~A: MISSING ~{~A~^,~}"
                                      scenario-id missing))))
        (make-t1-t6-lock-record
         :scenario-id           scenario-id
         :deterministic-command cmd
         :command-fingerprint   cmd-fp
         :artifact-root         artifact-root
         :artifact-pointers     pointers
         :transcript-digest     tx-digest
         :all-artifacts-present-p all-present
         :missing-artifacts     missing
         :detail                detail)))))

(defun compile-t1-t6-witness-ledger (matrix artifact-root)
  "Compile T1-T6 witness ledger from contract matrix, probing the artifact root."
  (declare (type tui-contract-matrix matrix)
           (type string artifact-root)
           (optimize (safety 3)))
  (let* ((records      (mapcar (lambda (row)
                                 (contract-row->lock-record row artifact-root))
                               (tcm-contracts matrix)))
         (all-present  (every #'tlr-all-artifacts-present-p records))
         (missing-cnt  (count-if-not #'tlr-all-artifacts-present-p records))
         (verdict      (if all-present :CLOSED :OPEN))
         (cmd          *tui-deterministic-command*)
         (cmd-fp       (sxhash cmd))
         (timestamp    (get-universal-time)))
    (make-t1-t6-witness-ledger
     :run-id               (format nil "t1-t6-ledger-~D" timestamp)
     :deterministic-command cmd
     :command-fingerprint  cmd-fp
     :records              records
     :all-present-p        all-present
     :missing-count        missing-cnt
     :closure-verdict      verdict
     :timestamp            timestamp
     :detail               (if all-present
                               "ALL_T1_T6_ARTIFACTS_WITNESSED"
                               (format nil "INCOMPLETE: ~D scenarios missing artifacts"
                                       missing-cnt)))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %tlr->json (r)
  (declare (type t1-t6-lock-record r))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"command_fingerprint\":~D,\"transcript_digest\":~D,\"all_present\":~A,\"missing_count\":~D,\"detail\":\"~A\"}"
            (tlr-scenario-id r)
            (tlr-command-fingerprint r)
            (tlr-transcript-digest r)
            (if (tlr-all-artifacts-present-p r) "true" "false")
            (length (tlr-missing-artifacts r))
            (tlr-detail r))))

(defun t1-t6-witness-ledger->json (ledger)
  "Serialize T1-T6 witness ledger to deterministic JSON."
  (declare (type t1-t6-witness-ledger ledger))
  (with-output-to-string (out)
    (format out "{\"run_id\":\"~A\",\"command\":\"~A\",\"command_fingerprint\":~D,\"all_present\":~A,\"missing_count\":~D,\"closure_verdict\":\"~A\",\"timestamp\":~D,\"detail\":\"~A\",\"records\":["
            (twl-run-id ledger)
            (twl-deterministic-command ledger)
            (twl-command-fingerprint ledger)
            (if (twl-all-present-p ledger) "true" "false")
            (twl-missing-count ledger)
            (twl-closure-verdict ledger)
            (twl-timestamp ledger)
            (twl-detail ledger))
    (loop for r in (twl-records ledger)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%tlr->json r) out)))
    (write-string "]}" out)))
