;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-rerun-command-table.lisp — T1-T6 deterministic rerun command table normalizer
;;; Bead: agent-orrery-v8uu

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(defstruct (tui-rerun-command-entry (:conc-name trce-))
  (scenario-id "" :type string)
  (expected-command "" :type string)
  (expected-hash 0 :type integer)
  (provided-hash 0 :type integer)
  (lineage-match-p nil :type boolean)
  (rerun-hint "" :type string))

(defstruct (tui-rerun-command-table (:conc-name trct-))
  (pass-p nil :type boolean)
  (command-table nil :type list)          ; list of tui-rerun-command-entry
  (drift-scenarios nil :type list)        ; scenarios with lineage drift
  (missing-scenarios nil :type list)      ; scenarios with missing lineage
  (match-count 0 :type integer)
  (drift-count 0 :type integer)
  (missing-count 0 :type integer)
  (deterministic-command "" :type string)
  (command-hash 0 :type integer)
  (detail "" :type string)
  (timestamp 0 :type integer))

;;; ── Declarations ─────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string) (values tui-rerun-command-entry &optional))
        build-tui-rerun-command-entry)
 (ftype (function (mcp-tui-scorecard-result) (values tui-rerun-command-table &optional))
        normalize-tui-rerun-command-table)
 (ftype (function (tui-rerun-command-table) (values string &optional))
        tui-rerun-command-table->json))

;;; ── JSON helper ──────────────────────────────────────────────────────────────

(defun %trce-json-escape (input)
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

;;; ── Entry builder ─────────────────────────────────────────────────────────────

(defun build-tui-rerun-command-entry (scenario-id)
  "Build a rerun command entry for a single TUI scenario."
  (declare (type string scenario-id)
           (optimize (safety 3)))
  (let* ((cmd *mcp-tui-deterministic-command*)
         (expected-hash (command-fingerprint cmd))
         (rerun-hint (format nil "cd /path/to/project && ~A --scenario ~A" cmd scenario-id)))
    (make-tui-rerun-command-entry
     :scenario-id scenario-id
     :expected-command cmd
     :expected-hash expected-hash
     :provided-hash 0 ; Will be populated from scorecard
     :lineage-match-p nil
     :rerun-hint rerun-hint)))

;;; ── Normalizer ────────────────────────────────────────────────────────────────

(defun normalize-tui-rerun-command-table (scorecard)
  "Normalize T1-T6 rerun command table from a scorecard result.
Returns TUI-RERUN-COMMAND-TABLE with per-scenario rerun hints."
  (declare (type mcp-tui-scorecard-result scorecard)
           (optimize (safety 3)))
  (let* ((cmd *mcp-tui-deterministic-command*)
         (expected-hash (command-fingerprint cmd))
         (provided-hash (mtsr-command-hash scorecard))
         (lineage-match-p (= expected-hash provided-hash))
         (entries nil)
         (drift nil)
         (missing nil)
         (match-count 0)
         (drift-count 0)
         (missing-count 0))
    ;; Build entry for each T1-T6 scenario
    (dolist (sid *mcp-tui-required-scenarios*)
      (let* ((entry (build-tui-rerun-command-entry sid))
             (scenario-missing (find sid (mtsr-missing-scenarios scorecard) :test #'string=)))
        ;; Populate provided hash from scorecard
        (setf (trce-provided-hash entry) provided-hash)
        (setf (trce-lineage-match-p entry) lineage-match-p)
        
        (cond
          ;; Missing scenario = missing lineage
          (scenario-missing
           (push sid missing)
           (incf missing-count))
          ;; Hash mismatch = drift
          ((not lineage-match-p)
           (push sid drift)
           (incf drift-count))
          ;; Otherwise match
          (t
           (incf match-count)))
        
        (push entry entries)))
    
    (setf entries (nreverse entries))
    (setf drift (nreverse drift))
    (setf missing (nreverse missing))
    
    (let* ((pass-p (and lineage-match-p
                        (mtsr-pass-p scorecard)
                        (= 0 drift-count)
                        (= 0 missing-count)))
           (detail (format nil "pass=~A match=~D drift=~D missing=~D cmd_match=~A"
                           pass-p match-count drift-count missing-count lineage-match-p)))
      (make-tui-rerun-command-table
       :pass-p pass-p
       :command-table entries
       :drift-scenarios drift
       :missing-scenarios missing
       :match-count match-count
       :drift-count drift-count
       :missing-count missing-count
       :deterministic-command cmd
       :command-hash provided-hash
       :detail detail
       :timestamp (get-universal-time)))))

;;; ── JSON serializer ───────────────────────────────────────────────────────────

(defun %rerun-entry->json (entry)
  (declare (type tui-rerun-command-entry entry))
  (format nil "{\"scenario\":\"~A\",\"expected_command\":\"~A\",\"expected_hash\":~D,\"provided_hash\":~D,\"lineage_match\":~A,\"rerun_hint\":\"~A\"}"
          (%trce-json-escape (trce-scenario-id entry))
          (%trce-json-escape (trce-expected-command entry))
          (trce-expected-hash entry)
          (trce-provided-hash entry)
          (if (trce-lineage-match-p entry) "true" "false")
          (%trce-json-escape (trce-rerun-hint entry))))

(defun tui-rerun-command-table->json (table)
  "Serialize TUI-RERUN-COMMAND-TABLE to JSON with command_table and rerun_hints."
  (declare (type tui-rerun-command-table table))
  (with-output-to-string (out)
    (format out "{\"pass\":~A,\"match_count\":~D,\"drift_count\":~D,\"missing_count\":~D,"
            (if (trct-pass-p table) "true" "false")
            (trct-match-count table)
            (trct-drift-count table)
            (trct-missing-count table))
    (format out "\"deterministic_command\":\"~A\",\"command_hash\":~D,"
            (%trce-json-escape (trct-deterministic-command table))
            (trct-command-hash table))
    ;; command_table array
    (format out "\"command_table\":[")
    (loop for entry in (trct-command-table table)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (write-string (%rerun-entry->json entry) out)))
    (format out "],\"drift_scenarios\":[")
    (loop for sid in (trct-drift-scenarios table)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~A\"" sid)))
    (format out "],\"missing_scenarios\":[")
    (loop for sid in (trct-missing-scenarios table)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~A\"" sid)))
    (format out "],\"detail\":\"~A\",\"timestamp\":~D}"
            (%trce-json-escape (trct-detail table))
            (trct-timestamp table))))
