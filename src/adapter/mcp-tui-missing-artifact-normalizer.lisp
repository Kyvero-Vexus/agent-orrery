;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-missing-artifact-normalizer.lisp — T1-T6 missing-artifact reason codes normalizer
;;; Bead: agent-orrery-wztc

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(deftype tui-artifact-kind ()
  '(member :screenshot :transcript :asciicast :machine-report))

(deftype tui-missing-reason-code ()
  '(member :artifact-not-found :path-invalid :manifest-drift :runner-mismatch :unknown))

(defparameter *tui-artifact-kind-order*
  '(:screenshot :transcript :asciicast :machine-report))

(defparameter *tui-missing-reason-code-order*
  '(:artifact-not-found :path-invalid :manifest-drift :runner-mismatch :unknown))

(defstruct (tui-missing-artifact-entry (:conc-name tmae-))
  (scenario-id "" :type string)
  (artifact-kind :screenshot :type tui-artifact-kind)
  (reason-code :artifact-not-found :type tui-missing-reason-code)
  (expected-path "" :type string)
  (remediation "" :type string))

(defstruct (tui-missing-artifact-report (:conc-name tmar-))
  (pass-p nil :type boolean)
  (total-missing 0 :type integer)
  (reason-code-matrix nil :type list)     ; list of tui-missing-artifact-entry
  (by-scenario nil :type list)            ; alist of (scenario-id . entries)
  (by-kind nil :type list)                ; alist of (kind . entries)
  (by-reason nil :type list)              ; alist of (reason . entries)
  (command-hash 0 :type integer)
  (detail "" :type string)
  (timestamp 0 :type integer))

;;; ── Declarations ─────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string tui-artifact-kind) (values string &optional))
        tui-artifact-expected-path)
 (ftype (function (mcp-tui-scenario-score tui-artifact-kind) (values tui-missing-artifact-entry &optional))
        build-missing-artifact-entry)
 (ftype (function (mcp-tui-scorecard-result) (values tui-missing-artifact-report &optional))
        normalize-tui-missing-artifacts)
 (ftype (function (tui-missing-artifact-report) (values string &optional))
        tui-missing-artifact-report->json))

;;; ── Expected paths ────────────────────────────────────────────────────────────

(defun tui-artifact-expected-path (scenario-id kind)
  "Return expected artifact path for a TUI scenario and artifact kind."
  (declare (type string scenario-id)
           (type tui-artifact-kind kind)
           (optimize (safety 3)))
  (case kind
    (:screenshot (format nil "artifacts/tui/~A/screenshot.png" scenario-id))
    (:transcript (format nil "artifacts/tui/~A/transcript.txt" scenario-id))
    (:asciicast (format nil "artifacts/tui/~A/recording.cast" scenario-id))
    (:machine-report (format nil "artifacts/tui/~A/report.json" scenario-id))))

;;; ── Entry builder ─────────────────────────────────────────────────────────────

(defun %remediation-for-missing (scenario-id kind)
  (declare (type string scenario-id)
           (type tui-artifact-kind kind))
  (format nil "rerun scenario ~A and ensure ~A artifact at expected path"
          scenario-id
          (string-downcase (symbol-name kind))))

(defun build-missing-artifact-entry (score kind)
  "Build a missing artifact entry for a scenario score and artifact kind."
  (declare (type mcp-tui-scenario-score score)
           (type tui-artifact-kind kind)
           (optimize (safety 3)))
  (let* ((scenario-id (mtss-scenario-id score))
         (expected-path (tui-artifact-expected-path scenario-id kind))
         (reason :artifact-not-found)
         (remediation (%remediation-for-missing scenario-id kind)))
    (make-tui-missing-artifact-entry
     :scenario-id scenario-id
     :artifact-kind kind
     :reason-code reason
     :expected-path expected-path
     :remediation remediation)))

;;; ── Normalizer ────────────────────────────────────────────────────────────────

(defun %collect-missing-for-score (score)
  (declare (type mcp-tui-scenario-score score))
  (let ((missing nil))
    (unless (mtss-screenshot-p score)
      (push (build-missing-artifact-entry score :screenshot) missing))
    (unless (mtss-transcript-p score)
      (push (build-missing-artifact-entry score :transcript) missing))
    (unless (mtss-asciicast-p score)
      (push (build-missing-artifact-entry score :asciicast) missing))
    (unless (mtss-report-p score)
      (push (build-missing-artifact-entry score :machine-report) missing))
    (nreverse missing)))

(defun %build-by-index (entries key-fn)
  (declare (type list entries)
           (type function key-fn))
  (let ((table (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (let ((key (funcall key-fn entry)))
        (push entry (gethash key table))))
    (let ((result nil))
      (maphash (lambda (k v)
                 (push (cons k (nreverse v)) result))
               table)
      (nreverse result))))

(defun normalize-tui-missing-artifacts (scorecard)
  "Normalize missing T1-T6 artifacts from a scorecard result.
Returns TUI-MISSING-ARTIFACT-REPORT with reason-code matrix and indices."
  (declare (type mcp-tui-scorecard-result scorecard)
           (optimize (safety 3)))
  (let* ((all-missing nil))
    ;; Collect all missing artifacts across T1-T6
    (dolist (score (mtsr-scenario-scores scorecard))
      (setf all-missing (append all-missing (%collect-missing-for-score score))))
    ;; Build indices
    (let* ((by-scenario (%build-by-index all-missing #'tmae-scenario-id))
           (by-kind (%build-by-index all-missing #'tmae-artifact-kind))
           (by-reason (%build-by-index all-missing #'tmae-reason-code))
           (total (length all-missing))
           (pass-p (and (mtsr-pass-p scorecard) (= total 0)))
           (detail (format nil "pass=~A missing=~D scenarios=~D kinds=~D reasons=~D"
                           pass-p total
                           (length by-scenario)
                           (length by-kind)
                           (length by-reason))))
      (make-tui-missing-artifact-report
       :pass-p pass-p
       :total-missing total
       :reason-code-matrix all-missing
       :by-scenario by-scenario
       :by-kind by-kind
       :by-reason by-reason
       :command-hash (mtsr-command-hash scorecard)
       :detail detail
       :timestamp (get-universal-time)))))

;;; ── JSON serializer ───────────────────────────────────────────────────────────

(defun %missing-entry->json (entry)
  (declare (type tui-missing-artifact-entry entry))
  (format nil "{\"scenario\":\"~A\",\"kind\":\"~(~A~)\",\"reason\":\"~(~A~)\",\"expected_path\":\"~A\",\"remediation\":\"~A\"}"
          (%json-escape (tmae-scenario-id entry))
          (tmae-artifact-kind entry)
          (tmae-reason-code entry)
          (%json-escape (tmae-expected-path entry))
          (%json-escape (tmae-remediation entry))))

(defun %index->json-pairs (index)
  (declare (type list index))
  (with-output-to-string (out)
    (loop for (key . entries) in index
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~A\":[" (if (symbolp key) (string-downcase (symbol-name key)) key))
               (loop for entry in entries
                     for j from 0
                     do (progn
                          (when (> j 0) (write-string "," out))
                          (write-string (%missing-entry->json entry) out)))
               (write-string "]" out)))))

(defun tui-missing-artifact-report->json (report)
  "Serialize TUI-MISSING-ARTIFACT-REPORT to JSON with reason-code matrix."
  (declare (type tui-missing-artifact-report report))
  (with-output-to-string (out)
    (format out "{\"pass\":~A,\"total_missing\":~D,\"command_hash\":~D,"
            (if (tmar-pass-p report) "true" "false")
            (tmar-total-missing report)
            (tmar-command-hash report))
    ;; reason_code_matrix array
    (format out "\"reason_code_matrix\":[")
    (loop for entry in (tmar-reason-code-matrix report)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (write-string (%missing-entry->json entry) out)))
    (format out "],\"by_scenario\":{")
    (write-string (%index->json-pairs (tmar-by-scenario report)) out)
    (format out "},\"by_kind\":{")
    (write-string (%index->json-pairs (tmar-by-kind report)) out)
    (format out "},\"by_reason\":{")
    (write-string (%index->json-pairs (tmar-by-reason report)) out)
    (format out "},\"detail\":\"~A\",\"timestamp\":~D}"
            (%json-escape (tmar-detail report))
            (tmar-timestamp report))))
