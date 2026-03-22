;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-command-table-verifier.lisp — typed S1-S6 attestation command-table verifier gate
;;; Bead: agent-orrery-91gj

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(defstruct (playwright-cmd-table-row (:conc-name pctr-))
  "Per-scenario command-table verification row."
  (scenario-id     ""    :type string)
  (provided-p      nil   :type boolean)
  (deterministic-p nil   :type boolean)
  (command-hash    0     :type integer)
  (expected-hash   0     :type integer)
  (hash-match-p    nil   :type boolean)
  (taxonomy-codes  nil   :type list)
  (detail          ""    :type string))

(defstruct (playwright-cmd-table-verdict (:conc-name pctv-))
  "Aggregate verdict for the S1-S6 command-table gate."
  (pass-p          nil   :type boolean)
  (rows            nil   :type list)     ; list of playwright-cmd-table-row
  (mismatch-count  0     :type integer)
  (missing-count   0     :type integer)
  (detail          ""    :type string)
  (timestamp       0     :type integer))

;;; ── Constants ────────────────────────────────────────────────────────────────

(defparameter *playwright-canonical-command*
  "cd e2e && ./run-e2e.sh"
  "Canonical deterministic command for Playwright S1-S6.")

(defparameter *playwright-canonical-command-hash*
  (command-fingerprint "cd e2e && ./run-e2e.sh")
  "Pre-computed fingerprint of the canonical Playwright command.")

;;; ── Taxonomy codes ────────────────────────────────────────────────────────────

(defun %cmd-table-taxonomy (scenario-id provided-p deterministic-p hash-match-p)
  (declare (type string scenario-id)
           (type boolean provided-p deterministic-p hash-match-p))
  (cond
    ((not provided-p)      (list (format nil "E4_CMD_TABLE_MISSING_~A" scenario-id)))
    ((not deterministic-p) (list (format nil "E4_CMD_TABLE_NONDETERMINISTIC_~A" scenario-id)))
    ((not hash-match-p)    (list (format nil "E4_CMD_TABLE_DRIFT_~A" scenario-id)))
    (t                     nil)))

;;; ── Row builder ──────────────────────────────────────────────────────────────

(defun %verify-cmd-table-row (scenario-id ledger)
  (declare (type string scenario-id)
           (type (or null playwright-scenario-ledger) ledger))
  (let* ((attestation
           (when ledger
             (find scenario-id (psl-attestations ledger)
                   :key #'wsa-scenario-id
                   :test #'string=)))
         (provided-p      (not (null attestation)))
         (cmd-hash        (if attestation
                              (wsa-command-fingerprint attestation)
                              0))
         (expected-hash   *playwright-canonical-command-hash*)
         (hash-match-p    (= cmd-hash expected-hash))
         ;; Deterministic: provided and hash matches canonical
         (deterministic-p (and provided-p hash-match-p))
         (taxonomy-codes  (%cmd-table-taxonomy scenario-id
                                               provided-p
                                               deterministic-p
                                               hash-match-p))
         (detail          (if (null taxonomy-codes)
                              (format nil "scenario ~A: cmd_hash=~D ok" scenario-id cmd-hash)
                              (format nil "scenario ~A: ~{~A~^,~}" scenario-id taxonomy-codes))))
    (make-playwright-cmd-table-row
     :scenario-id     scenario-id
     :provided-p      provided-p
     :deterministic-p deterministic-p
     :command-hash    cmd-hash
     :expected-hash   expected-hash
     :hash-match-p    hash-match-p
     :taxonomy-codes  taxonomy-codes
     :detail          detail)))

;;; ── Aggregate verifier ────────────────────────────────────────────────────────

(declaim
 (ftype (function ((or null playwright-scenario-ledger)) (values playwright-cmd-table-verdict &optional))
        verify-playwright-command-table)
 (ftype (function (playwright-cmd-table-verdict) (values string &optional))
        playwright-cmd-table-verdict->json))

(defun verify-playwright-command-table (ledger)
  "Verify S1-S6 Playwright attestation command-table fields against canonical expectations.
Returns a machine-checkable PLAYWRIGHT-CMD-TABLE-VERDICT with per-scenario rows."
  (declare (type (or null playwright-scenario-ledger) ledger)
           (optimize (safety 3)))
  (let* ((rows (mapcar (lambda (sid) (%verify-cmd-table-row sid ledger))
                       *playwright-required-scenarios*))
         (mismatch-count (count-if (lambda (r) (not (null (pctr-taxonomy-codes r)))) rows))
         (missing-count  (count-if (lambda (r) (not (pctr-provided-p r))) rows))
         (pass-p         (zerop mismatch-count))
         (detail         (format nil "pass=~A mismatches=~D missing=~D"
                                 pass-p mismatch-count missing-count)))
    (make-playwright-cmd-table-verdict
     :pass-p         pass-p
     :rows           rows
     :mismatch-count mismatch-count
     :missing-count  missing-count
     :detail         detail
     :timestamp      (get-universal-time))))

;;; ── JSON serializer ───────────────────────────────────────────────────────────

(defun %cmd-table-row->json (row)
  (declare (type playwright-cmd-table-row row))
  (with-output-to-string (out)
    (format out
            "{\"scenario\":\"~A\",\"provided\":~A,\"deterministic\":~A,\"command_hash\":~D,\"expected_hash\":~D,\"hash_match\":~A,\"taxonomy\":["
            (pctr-scenario-id row)
            (if (pctr-provided-p row)      "true" "false")
            (if (pctr-deterministic-p row) "true" "false")
            (pctr-command-hash row)
            (pctr-expected-hash row)
            (if (pctr-hash-match-p row)    "true" "false"))
    (loop for code in (pctr-taxonomy-codes row)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out "\"~A\"" code)))
    (format out "],\"detail\":\"~A\"}" (pctr-detail row))))

(defun playwright-cmd-table-verdict->json (verdict)
  "Serialise PLAYWRIGHT-CMD-TABLE-VERDICT to a machine-readable JSON string."
  (declare (type playwright-cmd-table-verdict verdict))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"mismatch_count\":~D,\"missing_count\":~D,\"rows\":["
            (if (pctv-pass-p verdict) "true" "false")
            (pctv-mismatch-count verdict)
            (pctv-missing-count verdict))
    (loop for row in (pctv-rows verdict)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (write-string (%cmd-table-row->json row) out)))
    (format out "],\"detail\":\"~A\",\"timestamp\":~D}"
            (pctv-detail verdict)
            (pctv-timestamp verdict))))
