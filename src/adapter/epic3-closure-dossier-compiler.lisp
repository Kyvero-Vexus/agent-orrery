;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic3-closure-dossier-compiler.lisp — typed T1-T6 closure dossier compiler
;;; Bead: agent-orrery-li1j
;;;
;;; Ingests mcp-tui-driver T1-T6 witness/lock outputs and emits deterministic,
;;; machine-checkable closure packets. Fail-closed: any missing artifact or
;;; command drift produces :OPEN verdict with diagnostics.

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype dossier-verdict ()
  '(member :closed :open))

(deftype dossier-diagnostic-category ()
  '(member :pass :missing-artifact :command-drift :digest-mismatch :no-witness :no-journal))

(defstruct (epic3-diagnostic (:conc-name ed-))
  "Single fail-closed diagnostic for Epic 3 closure."
  (scenario-id ""  :type string)
  (category :pass  :type dossier-diagnostic-category)
  (expected-paths nil :type list)
  (actual-paths nil :type list)
  (detail "" :type string))

(defstruct (epic3-scenario-record (:conc-name esr-))
  "Per-scenario closure record for T1-T6."
  (scenario-id "" :type string)
  (command-fingerprint 0 :type integer)
  (transcript-digest 0 :type integer)
  (artifacts-present-p nil :type boolean)
  (artifact-paths nil :type list)
  (artifact-digests nil :type list)
  (verdict :missing :type (member :pass :fail :missing)))

(defstruct (artifact-digest-entry (:conc-name ade-))
  "Digest entry for one artifact."
  (path "" :type string)
  (digest "" :type string))

(defstruct (epic3-closure-dossier (:conc-name ecd-))
  "Machine-checkable closure dossier for Epic 3 T1-T6."
  (run-id "" :type string)
  (deterministic-command "" :type string)
  (command-fingerprint 0 :type integer)
  (scenario-coverage 0.0 :type single-float)
  (records nil :type list)                 ; list of epic3-scenario-record
  (artifact-digest-map nil :type list)     ; list of artifact-digest-entry
  (transcript-attestations nil :type list) ; (scenario-id . hash) pairs
  (fail-closed-diagnostics nil :type list) ; list of epic3-diagnostic
  (closure-verdict :open :type dossier-verdict)
  (timestamp 0 :type integer)
  (policy-note "Epic 3 MUST NOT be reported closed without mcp-tui-driver-backed T1-T6 evidence." :type string))

;;; ── Declaims ─────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (t1-t6-lock-record) (values epic3-scenario-record &optional))
        lock-record->scenario-record)
 (ftype (function (t1-t6-witness-ledger t1-t6-replay-journal t1-t6-closure-verdict)
          (values epic3-closure-dossier &optional))
        compile-epic3-closure-dossier)
 (ftype (function (epic3-closure-dossier) (values string &optional))
        epic3-closure-dossier->json)
 (ftype (function (string) (values string &optional))
        %file-sha256-or-empty)
 (ftype (function (t1-t6-lock-record) (values list &optional))
        %extract-artifact-digests))

;;; ── Internal utilities ───────────────────────────────────────────────────────

(defun %file-sha256-or-empty (path)
  "Return a deterministic digest string of file at PATH, or empty string if not found.
Uses sxhash of file content as a portable digest proxy."
  (declare (type string path)
           (optimize (safety 3)))
  (handler-case
      (with-open-file (s path :element-type '(unsigned-byte 8))
        (let* ((len (file-length s))
               (buf (make-array len :element-type '(unsigned-byte 8))))
          (read-sequence buf s)
          (format nil "~16,'0X" (sxhash buf))))
    (error () "")))

(defun %extract-artifact-digests (lock-record)
  "Extract artifact digests from a lock record."
  (declare (type t1-t6-lock-record lock-record))
  (let ((digests nil))
    (dolist (path (tlr-artifact-pointers lock-record))
      (let ((digest (%file-sha256-or-empty path)))
        (when (plusp (length digest))
          (push (make-artifact-digest-entry :path path :digest digest) digests))))
    (nreverse digests)))

(defun lock-record->scenario-record (lock-record)
  "Convert a T1-T6 lock record to a closure scenario record."
  (declare (type t1-t6-lock-record lock-record)
           (optimize (safety 3)))
  (let* ((artifact-digests (%extract-artifact-digests lock-record))
         (present-p (tlr-all-artifacts-present-p lock-record))
         (verdict (if present-p :pass :fail)))
    (make-epic3-scenario-record
     :scenario-id (tlr-scenario-id lock-record)
     :command-fingerprint (tlr-command-fingerprint lock-record)
     :transcript-digest (tlr-transcript-digest lock-record)
     :artifacts-present-p present-p
     :artifact-paths (tlr-artifact-pointers lock-record)
     :artifact-digests artifact-digests
     :verdict verdict)))

(defun %build-diagnostic (scenario-id category expected actual detail)
  "Build a single diagnostic."
  (declare (type string scenario-id detail)
           (type dossier-diagnostic-category category)
           (type list expected actual))
  (make-epic3-diagnostic
   :scenario-id scenario-id
   :category category
   :expected-paths expected
   :actual-paths actual
   :detail detail))

(defun %scenario-diagnostics (record lock-record)
  "Generate diagnostics for one scenario."
  (declare (type epic3-scenario-record record)
           (type t1-t6-lock-record lock-record))
  (cond
    ((esr-artifacts-present-p record)
     (list (%build-diagnostic
            (esr-scenario-id record) :pass
            nil nil
            (format nil "~A: all artifacts present" (esr-scenario-id record)))))
    ((tlr-missing-artifacts lock-record)
     (list (%build-diagnostic
            (esr-scenario-id record) :missing-artifact
            (tlr-missing-artifacts lock-record)
            (esr-artifact-paths record)
            (format nil "~A: missing ~{~A~^, ~}"
                    (esr-scenario-id record)
                    (tlr-missing-artifacts lock-record)))))
    (t
     (list (%build-diagnostic
            (esr-scenario-id record) :missing-artifact
            nil nil
            (format nil "~A: incomplete" (esr-scenario-id record)))))))

;;; ── Core compiler ────────────────────────────────────────────────────────────

(defun compile-epic3-closure-dossier (ledger journal verdict)
  "Compile closure dossier from T1-T6 witness ledger, replay journal, and closure verdict.
Returns an EPIC3-CLOSURE-DOSSIER with deterministic JSON shape."
  (declare (type t1-t6-witness-ledger ledger)
           (type t1-t6-replay-journal journal)
           (type t1-t6-closure-verdict verdict)
           (optimize (safety 3)))
  (let* ((records (mapcar #'lock-record->scenario-record (twl-records ledger)))
         (all-present-p (every #'esr-artifacts-present-p records))
         (cmd-canonical-p (verdict-command-canonical-p verdict))
         (verdict-closed-p (eq (verdict-verdict verdict) :closed))
         (complete-p (and all-present-p cmd-canonical-p verdict-closed-p))
         (coverage (/ (count-if #'esr-artifacts-present-p records) 6.0))
         (diagnostics nil)
         (digest-map nil)
         (tx-attestations nil))
    ;; Build diagnostics
    (loop for rec in records
          for lock in (twl-records ledger)
          do (setf diagnostics (append diagnostics (%scenario-diagnostics rec lock))))
    ;; Build artifact digest map
    (dolist (rec records)
      (dolist (entry (esr-artifact-digests rec))
        (push entry digest-map))
      (push (cons (esr-scenario-id rec) (esr-transcript-digest rec)) tx-attestations))
    ;; Final verdict
    (let ((closure-verdict (if complete-p :closed :open)))
      (make-epic3-closure-dossier
       :run-id (format nil "epic3-dossier-~D" (get-universal-time))
       :deterministic-command *tui-deterministic-command*
       :command-fingerprint (sxhash *tui-deterministic-command*)
       :scenario-coverage coverage
       :records records
       :artifact-digest-map (nreverse digest-map)
       :transcript-attestations (nreverse tx-attestations)
       :fail-closed-diagnostics diagnostics
       :closure-verdict closure-verdict
       :timestamp (get-universal-time)))))

;;; ── JSON serialization ───────────────────────────────────────────────────────

(defun %diagnostic->json (d)
  (declare (type epic3-diagnostic d))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"category\":\"~(~A~)\",\"expected\":["
            (ed-scenario-id d) (ed-category d))
    (loop for p in (ed-expected-paths d) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" p)))
    (format out "],\"actual\":[")
    (loop for p in (ed-actual-paths d) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" p)))
    (format out "],\"detail\":\"~A\"}" (ed-detail d))))

(defun %scenario-record->json (r)
  (declare (type epic3-scenario-record r))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"cmd_fp\":~D,\"tx_digest\":~D,\"artifacts\":~A,\"verdict\":\"~(~A~)\",\"paths\":["
            (esr-scenario-id r)
            (esr-command-fingerprint r)
            (esr-transcript-digest r)
            (if (esr-artifacts-present-p r) "true" "false")
            (esr-verdict r))
    (loop for p in (esr-artifact-paths r) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" p)))
    (write-string "]}" out)))

(defun %digest-entry->json (e)
  (declare (type artifact-digest-entry e))
  (format nil "{\"path\":\"~A\",\"digest\":\"~A\"}"
          (ade-path e) (ade-digest e)))

(defun epic3-closure-dossier->json (dossier)
  "Serialize EPIC3-CLOSURE-DOSSIER to deterministic JSON."
  (declare (type epic3-closure-dossier dossier))
  (with-output-to-string (out)
    (format out "{\"run_id\":\"~A\",\"command\":\"~A\",\"cmd_fp\":~D,\"coverage\":~4,2F,\"verdict\":\"~(~A~)\",\"timestamp\":~D,"
            (ecd-run-id dossier)
            (ecd-deterministic-command dossier)
            (ecd-command-fingerprint dossier)
            (ecd-scenario-coverage dossier)
            (ecd-closure-verdict dossier)
            (ecd-timestamp dossier))
    ;; Records
    (write-string "\"records\":[" out)
    (loop for r in (ecd-records dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%scenario-record->json r) out)))
    (write-string "],\"artifact_digests\":[" out)
    ;; Digests
    (loop for e in (ecd-artifact-digest-map dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%digest-entry->json e) out)))
    (write-string "],\"tx_attestations\":{" out)
    ;; Transcript attestations
    (loop for (sid . hash) in (ecd-transcript-attestations dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\":~D" sid hash)))
    (write-string "},\"diagnostics\":[" out)
    ;; Diagnostics
    (loop for d in (ecd-fail-closed-diagnostics dossier) for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%diagnostic->json d) out)))
    (format out "],\"policy_note\":\"~A\"}" (ecd-policy-note dossier))))

;;; ── CLI entry point ──────────────────────────────────────────────────────────

(defun run-epic3-closure-dossier-compiler (artifact-root output-path)
  "Run the closure dossier compiler and write JSON to OUTPUT-PATH."
  (declare (type string artifact-root output-path))
  ;; Build minimal inputs for compilation
  (let* ((matrix (make-tui-contract-matrix
                  :contracts (mapcar (lambda (sid)
                                       (make-tui-contract-row
                                        :scenario-id sid
                                        :command *tui-deterministic-command*
                                        :command-hash (sxhash *tui-deterministic-command*)
                                        :transcript-hash 0))
                                     '("T1" "T2" "T3" "T4" "T5" "T6"))))
         (ledger (compile-t1-t6-witness-ledger matrix artifact-root))
         (journal (make-empty-journal))
         (verdict (make-t1-t6-closure-verdict
                   :verdict :incomplete
                   :command-canonical-p t
                   :complete-p nil
                   :findings nil
                   :pack-hash (format nil "bootstrap-~D" (get-universal-time))
                   :assessed-at (format nil "~D" (get-universal-time))))
         (dossier (compile-epic3-closure-dossier ledger journal verdict))
         (json (epic3-closure-dossier->json dossier)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string json s))
    (format t "~&Epic 3 Closure Dossier: ~A~%" (ecd-closure-verdict dossier))
    (format t "  Coverage: ~4,2F%~%" (* 100 (ecd-scenario-coverage dossier)))
    (format t "  Records: ~D~%" (length (ecd-records dossier)))
    (format t "  Written to: ~A~%" output-path)
    dossier))
