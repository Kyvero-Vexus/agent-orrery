;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-attestation-merger.lisp — typed S1-S6 canonical attestation merger for unified closure envelopes
;;; Bead: agent-orrery-k75i

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype pw-merger-taxonomy-code ()
  '(member :missing-attestation :command-drift :missing-screenshot :missing-trace))

(defparameter *pw-merger-taxonomy-order*
  '(:missing-attestation :command-drift :missing-screenshot :missing-trace))

(defstruct (pw-envelope-row (:conc-name pwer-)
            (:constructor make-pw-envelope-row
                (&key scenario-id pass-p command-hash expected-hash hash-match-p
                      screenshot-present-p trace-present-p taxonomy-codes detail)))
  (scenario-id "" :type string)
  (pass-p nil :type boolean)
  (command-hash 0 :type integer)
  (expected-hash 0 :type integer)
  (hash-match-p nil :type boolean)
  (screenshot-present-p nil :type boolean)
  (trace-present-p nil :type boolean)
  (taxonomy-codes '() :type list)
  (detail "" :type string))

(defstruct (pw-attestation-merger-report (:conc-name pwam-)
            (:constructor make-pw-attestation-merger-report
                (&key pass-p command-match-p rows missing-scenarios drift-scenarios
                      command-hash expected-hash detail timestamp)))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (rows '() :type list)
  (missing-scenarios '() :type list)
  (drift-scenarios '() :type list)
  (command-hash 0 :type integer)
  (expected-hash 0 :type integer)
  (detail "" :type string)
  (timestamp 0 :type integer))

;;; ── Declarations ─────────────────────────────────────────────────────────────

(declaim
 (ftype (function (web-scenario-attestation integer integer) (values pw-envelope-row &optional))
        %build-envelope-row)
 (ftype (function ((or null playwright-scenario-ledger)) (values pw-attestation-merger-report &optional))
        merge-playwright-attestations->envelope)
 (ftype (function (pw-attestation-merger-report) (values string &optional))
        pw-attestation-merger-report->json))

;;; ── Row builder ──────────────────────────────────────────────────────────────

(defun %taxonomy-for-row (attestation-p hash-match-p screen-p trace-p)
  (declare (type boolean attestation-p hash-match-p screen-p trace-p)
           (optimize (safety 3)))
  (let ((codes nil))
    (unless attestation-p
      (push :missing-attestation codes))
    (unless hash-match-p
      (push :command-drift codes))
    (unless screen-p
      (push :missing-screenshot codes))
    (unless trace-p
      (push :missing-trace codes))
    ;; Order by canonical taxonomy
    (let ((ordered nil))
      (dolist (canonical *pw-merger-taxonomy-order*)
        (when (find canonical codes :test #'eq)
          (push canonical ordered)))
      (nreverse ordered))))

(defun %build-envelope-row (attestation expected-hash canonical-hash)
  (declare (type web-scenario-attestation attestation)
           (type integer expected-hash canonical-hash)
           (optimize (safety 3)))
  (let* ((scenario-id (wsa-scenario-id attestation))
         (cmd-hash (wsa-command-fingerprint attestation))
         (hash-match-p (= cmd-hash canonical-hash))
         (screen-p (plusp (length (wsa-screenshot-path attestation))))
         (trace-p (plusp (length (wsa-trace-path attestation))))
         (attested-p (wsa-attested-p attestation))
         (taxonomy (%taxonomy-for-row attested-p hash-match-p screen-p trace-p))
         (pass-p (and attested-p hash-match-p screen-p trace-p (null taxonomy)))
         (detail (if pass-p
                     (format nil "scenario ~A: ok" scenario-id)
                     (format nil "scenario ~A: ~{~A~^,~}" scenario-id taxonomy))))
    (make-pw-envelope-row
     :scenario-id scenario-id
     :pass-p pass-p
     :command-hash cmd-hash
     :expected-hash expected-hash
     :hash-match-p hash-match-p
     :screenshot-present-p screen-p
     :trace-present-p trace-p
     :taxonomy-codes taxonomy
     :detail detail)))

(defun %missing-row (scenario-id expected-hash)
  (declare (type string scenario-id)
           (type integer expected-hash)
           (optimize (safety 3)))
  (let ((taxonomy '(:missing-attestation)))
    (make-pw-envelope-row
     :scenario-id scenario-id
     :pass-p nil
     :command-hash 0
     :expected-hash expected-hash
     :hash-match-p nil
     :screenshot-present-p nil
     :trace-present-p nil
     :taxonomy-codes taxonomy
     :detail (format nil "scenario ~A: missing attestation" scenario-id))))

;;; ── Merger ───────────────────────────────────────────────────────────────────

(defun merge-playwright-attestations->envelope (ledger)
  "Merge Playwright S1-S6 attestations into canonical closure-envelope shape.
Returns a PW-ATTESTATION-MERGER-REPORT with deterministic JSON ordering and fail-closed checks."
  (declare (type (or null playwright-scenario-ledger) ledger)
           (optimize (safety 3)))
  (let* ((canonical-hash *playwright-canonical-command-hash*)
         (expected-hash canonical-hash)
         (rows nil)
         (missing nil)
         (drift nil))
    ;; Process each required scenario in deterministic order (S1-S6)
    (dolist (sid *playwright-required-scenarios*)
      (let* ((att (when ledger
                    (find sid (psl-attestations ledger)
                          :key #'wsa-scenario-id
                          :test #'string=)))
             (row (if att
                      (%build-envelope-row att expected-hash canonical-hash)
                      (%missing-row sid expected-hash))))
        (push row rows)
        (unless (pwer-pass-p row)
          (when (find :missing-attestation (pwer-taxonomy-codes row))
            (push sid missing))
          (unless (pwer-hash-match-p row)
            (push sid drift)))))
    (setf rows (nreverse rows))
    (setf missing (nreverse missing))
    (setf drift (nreverse drift))
    (let* ((pass-p (and (null missing) (null drift)
                        (every #'pwer-pass-p rows)))
           (cmd-match (if ledger
                          (= (command-fingerprint (psl-command ledger)) canonical-hash)
                          nil))
           (detail (format nil "pass=~A missing=~D drift=~D cmd_match=~A"
                           pass-p (length missing) (length drift) cmd-match)))
      (make-pw-attestation-merger-report
       :pass-p pass-p
       :command-match-p cmd-match
       :rows rows
       :missing-scenarios missing
       :drift-scenarios drift
       :command-hash (if ledger (command-fingerprint (psl-command ledger)) 0)
       :expected-hash expected-hash
       :detail detail
       :timestamp (get-universal-time)))))

;;; ── JSON serializer ───────────────────────────────────────────────────────────

(defun %envelope-row->json (row)
  (declare (type pw-envelope-row row))
  (with-output-to-string (out)
    (format out
            "{\"scenario\":\"~A\",\"pass\":~A,\"command_hash\":~D,\"expected_hash\":~D,\"hash_match\":~A,\"screenshot_present\":~A,\"trace_present\":~A,\"taxonomy\":["
            (pwer-scenario-id row)
            (if (pwer-pass-p row) "true" "false")
            (pwer-command-hash row)
            (pwer-expected-hash row)
            (if (pwer-hash-match-p row) "true" "false")
            (if (pwer-screenshot-present-p row) "true" "false")
            (if (pwer-trace-present-p row) "true" "false"))
    (loop for code in (pwer-taxonomy-codes row)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out "\"~(~A~)\"" code)))
    (format out "],\"detail\":\"~A\"}" (pwer-detail row))))

(defun pw-attestation-merger-report->json (report)
  "Serialize PW-ATTESTATION-MERGER-REPORT to deterministic JSON."
  (declare (type pw-attestation-merger-report report))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"command_match\":~A,\"command_hash\":~D,\"expected_hash\":~D,\"missing_scenarios\":["
            (if (pwam-pass-p report) "true" "false")
            (if (pwam-command-match-p report) "true" "false")
            (pwam-command-hash report)
            (pwam-expected-hash report))
    ;; Missing scenarios in deterministic order
    (loop for sid in (pwam-missing-scenarios report)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out "\"~A\"" sid)))
    (format out "],\"drift_scenarios\":[")
    ;; Drift scenarios in deterministic order
    (loop for sid in (pwam-drift-scenarios report)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out "\"~A\"" sid)))
    (format out "],\"rows\":[")
    ;; Rows in S1-S6 order
    (loop for row in (pwam-rows report)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (write-string (%envelope-row->json row) out)))
    (format out "],\"detail\":\"~A\",\"timestamp\":~D}"
            (pwam-detail report)
            (pwam-timestamp report))))
