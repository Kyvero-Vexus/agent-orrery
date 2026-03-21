;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-unified-envelope-projector.lisp — Epic 3 unified-envelope projector
;;; Bead: agent-orrery-8a3x

(in-package #:orrery/adapter)

(deftype ingestion-taxonomy-code ()
  '(member :missing-field :type-mismatch :command-drift :artifact-gap))

(defparameter *mcp-tui-drift-taxonomy-order*
  '(:missing-field :type-mismatch :command-drift :artifact-gap))

(defstruct (mcp-tui-envelope-row (:conc-name mter-)
            (:constructor make-mcp-tui-envelope-row
                (&key scenario-id pass-p command-hash taxonomy-codes artifact-count
                      missing-artifact-kinds detail)))
  (scenario-id "" :type string)
  (pass-p nil :type boolean)
  (command-hash 0 :type integer)
  (taxonomy-codes '() :type list)
  (artifact-count 0 :type (integer 0))
  (missing-artifact-kinds '() :type list)
  (detail "" :type string))

(defstruct (mcp-tui-envelope-report (:conc-name mtep-)
            (:constructor make-mcp-tui-envelope-report
                (&key pass-p command-match-p rows detail timestamp)))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (rows '() :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string) (values boolean &optional)) %known-tui-scenario-id-p)
 (ftype (function (mcp-tui-ingestion-scenario integer boolean) (values mcp-tui-envelope-row &optional))
        ingestion-scenario->envelope-row)
 (ftype (function (mcp-tui-ingestion-result) (values mcp-tui-envelope-report &optional))
        project-mcp-tui-ingestion->unified-envelope)
 (ftype (function (string string) (values mcp-tui-envelope-report &optional))
        project-mcp-tui-unified-envelope)
 (ftype (function (mcp-tui-envelope-report) (values string &optional))
        mcp-tui-envelope-report->json)
 (ftype (function (mcp-tui-envelope-report) (values string &optional))
        mcp-tui-unified-envelope->json))

(defun %known-tui-scenario-id-p (sid)
  (declare (type string sid)
           (optimize (safety 3)))
  (not (null (find sid *mcp-tui-required-scenarios* :test #'string=))) )

(defun %taxonomy-codes-for-row (row command-match-p)
  (declare (type mcp-tui-ingestion-scenario row)
           (type boolean command-match-p)
           (optimize (safety 3)))
  (let ((codes nil))
    (unless command-match-p
      (push :command-drift codes))
    (unless (%known-tui-scenario-id-p (mtis-scenario-id row))
      (push :type-mismatch codes))
    (when (null (mtis-detail row))
      (push :missing-field codes))
    (when (plusp (length (mtis-missing-artifact-kinds row)))
      (push :artifact-gap codes))
    (let ((ordered nil))
      (dolist (canonical *mcp-tui-drift-taxonomy-order*)
        (when (find canonical codes :test #'eq)
          (push canonical ordered)))
      (nreverse ordered))))

(defun ingestion-scenario->envelope-row (row command-hash command-match-p)
  (declare (type mcp-tui-ingestion-scenario row)
           (type integer command-hash)
           (type boolean command-match-p)
           (optimize (safety 3)))
  (make-mcp-tui-envelope-row
   :scenario-id (mtis-scenario-id row)
   :pass-p (and command-match-p (mtis-pass-p row) (%known-tui-scenario-id-p (mtis-scenario-id row)))
   :command-hash command-hash
   :taxonomy-codes (%taxonomy-codes-for-row row command-match-p)
   :artifact-count (mtis-artifact-count row)
   :missing-artifact-kinds (mtis-missing-artifact-kinds row)
   :detail (mtis-detail row)))

(defun project-mcp-tui-ingestion->unified-envelope (result)
  (declare (type mcp-tui-ingestion-result result)
           (optimize (safety 3)))
  (let ((rows nil))
    (dolist (row (mtir-scenario-results result))
      (push (ingestion-scenario->envelope-row row
                                              (mtir-command-fingerprint result)
                                              (mtir-command-match-p result))
            rows))
    (setf rows (nreverse rows))
    (make-mcp-tui-envelope-report
     :pass-p (and (mtir-pass-p result) (every #'mter-pass-p rows))
     :command-match-p (mtir-command-match-p result)
     :rows rows
     :detail (if (and (mtir-pass-p result) (every #'mter-pass-p rows))
                 "Epic 3 unified-envelope projection passed: deterministic mcp-tui-driver evidence is complete."
                 "Epic 3 unified-envelope projection failed: schema-drift taxonomy contains blocking diagnostics.")
     :timestamp (mtir-timestamp result))))

(defun project-mcp-tui-unified-envelope (artifacts-dir command)
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (project-mcp-tui-ingestion->unified-envelope
   (evaluate-mcp-tui-ingestion-adapter artifacts-dir command)))

(defun %json-escape-mtep (s)
  (declare (type string s)
           (optimize (safety 3)))
  (with-output-to-string (out)
    (loop for ch across s do
      (case ch
        (#\\ (write-string "\\\\" out))
        (#\" (write-string "\\\"" out))
        (#\Newline (write-string "\\n" out))
        (t (write-char ch out))))))

(defun mcp-tui-envelope-report->json (report)
  (declare (type mcp-tui-envelope-report report)
           (optimize (safety 3)))
  ;; Stable ordering is intentional for deterministic diffability.
  (with-output-to-string (s)
    (format s
            "{\"schema\":\"ep3-mcp-tui-unified-envelope-v1\",\"pass\":~A,\"framework\":\"mcp-tui-driver\",\"deterministic_command\":\"~A\",\"command_match\":~A,\"command_hash\":~D,\"rows\":["
            (if (mtep-pass-p report) "true" "false")
            (%json-escape-mtep *mcp-tui-deterministic-command*)
            (if (mtep-command-match-p report) "true" "false")
            (if (endp (mtep-rows report))
                0
                (mter-command-hash (first (mtep-rows report)))))
    (loop for row in (mtep-rows report)
          for i from 0 do
            (when (> i 0) (write-char #\, s))
            (format s
                    "{\"scenario_id\":\"~A\",\"pass\":~A,\"command_hash\":~D,\"taxonomy_codes\":["
                    (%json-escape-mtep (mter-scenario-id row))
                    (if (mter-pass-p row) "true" "false")
                    (mter-command-hash row))
            (loop for code in (mter-taxonomy-codes row)
                  for j from 0 do
                    (when (> j 0) (write-char #\, s))
                    (format s "\"~(~A~)\"" code))
            (write-string "],\"artifact_count\":" s)
            (format s "~D" (mter-artifact-count row))
            (write-string ",\"missing_artifact_kinds\":[" s)
            (loop for kind in (mter-missing-artifact-kinds row)
                  for k from 0 do
                    (when (> k 0) (write-char #\, s))
                    (format s "\"~(~A~)\"" kind))
            (format s "],\"detail\":\"~A\"}" (%json-escape-mtep (mter-detail row))))
    (format s "],\"detail\":\"~A\",\"timestamp\":~D}"
            (%json-escape-mtep (mtep-detail report))
            (mtep-timestamp report))))

(defun mcp-tui-unified-envelope->json (report)
  (declare (type mcp-tui-envelope-report report)
           (optimize (safety 3)))
  (mcp-tui-envelope-report->json report))
