;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; anomaly-detector.lisp — CL bridge for typed Coalton anomaly detection
;;;
;;; Bead: agent-orrery-mhg
;;; Pure orchestration over normalized usage/session snapshots.
;;; No I/O side effects.

(in-package #:orrery/adapter)

(deftype anomaly-label ()
  '(member :none :warning :critical))

(defstruct (adapter-anomaly-snapshot
             (:constructor make-adapter-anomaly-snapshot
                 (&key adapter-id session-count usage-records)))
  "Normalized adapter snapshot used for anomaly drift comparison."
  (adapter-id "" :type string)
  (session-count 0 :type fixnum)
  (usage-records '() :type list))

(defstruct (adapter-anomaly-result
             (:constructor make-adapter-anomaly-result
                 (&key primary-adapter secondary-adapter
                       report divergence-findings
                       anomaly-count risk-score severity-label)))
  "Cross-adapter anomaly evaluation result suitable for dashboards/alerts."
  (primary-adapter "" :type string)
  (secondary-adapter "" :type string)
  (report nil :type t)
  (divergence-findings '() :type list)
  (anomaly-count 0 :type fixnum)
  (risk-score 0 :type fixnum)
  (severity-label :none :type anomaly-label))

(declaim
 (ftype (function (list string) (values t &optional)) %usage-summary)
 (ftype (function (t) (values t &optional)) %summary-top-models)
 (ftype (function (string) (values anomaly-label &optional)) %severity-text->label)
 (ftype (function (adapter-anomaly-snapshot adapter-anomaly-snapshot
                   &key (:thresholds t))
                  (values adapter-anomaly-result &optional))
        detect-adapter-anomalies)
 (ftype (function (adapter-anomaly-snapshot) (values string &optional))
        snapshot->json)
 (ftype (function (adapter-anomaly-result) (values string &optional))
        anomaly-result->json))

(defun %usage-summary (usage-records period-label)
  "Build Coalton usage summary from normalized usage records."
  (declare (type list usage-records)
           (type string period-label)
           (optimize (safety 3)))
  (let* ((bucket (usage-records->coalton-bucket usage-records period-label)))
    (orrery/coalton/core:cl-build-summary (list bucket))))

(defun %summary-top-models (summary)
  "Extract Coalton model-rank list from UsageSummary."
  (declare (optimize (safety 3)))
  (orrery/coalton/core:cl-summary-top-models summary))

(defun %severity-text->label (text)
  "Map severity text label to CL keyword label."
  (declare (type string text)
           (optimize (safety 3)))
  (cond
    ((string= text "critical") :critical)
    ((string= text "warning") :warning)
    (t :none)))

(defun detect-adapter-anomalies (current baseline &key (thresholds (orrery/coalton/core:cl-default-thresholds)))
  "Run typed anomaly detection for session/cost/token/model drift between
   two adapter snapshots (CURRENT vs BASELINE).

   Returns adapter-anomaly-result containing:
   - Coalton anomaly report
   - explicit adapter divergence findings
   - flattened severity/risk metadata for dashboards/alerts

   Pure function (no network/process I/O)."
  (declare (type adapter-anomaly-snapshot current baseline)
           (optimize (safety 3)))
  (let* ((cur-summary (%usage-summary (adapter-anomaly-snapshot-usage-records current) "current"))
         (base-summary (%usage-summary (adapter-anomaly-snapshot-usage-records baseline) "baseline"))
         (cur-tokens (orrery/coalton/core:cl-summary-total-tokens cur-summary))
         (base-tokens (orrery/coalton/core:cl-summary-total-tokens base-summary))
         (cur-cost (orrery/coalton/core:cl-summary-total-cost cur-summary))
         (base-cost (orrery/coalton/core:cl-summary-total-cost base-summary))
         (cur-models (%summary-top-models cur-summary))
         (base-models (%summary-top-models base-summary))
         (report (orrery/coalton/core:cl-run-anomaly-pipeline
                  thresholds
                  (adapter-anomaly-snapshot-session-count current)
                  (adapter-anomaly-snapshot-session-count baseline)
                  cur-cost base-cost
                  cur-tokens base-tokens
                  cur-models base-models))
         (divergence (orrery/coalton/core:cl-detect-adapter-divergence
                      thresholds cur-tokens base-tokens))
         (count (the fixnum (orrery/coalton/core:cl-anomaly-report-count report)))
         (risk (the fixnum (orrery/coalton/core:cl-anomaly-report-risk-score report)))
         (severity (%severity-text->label
                    (orrery/coalton/core:cl-anomaly-report-worst-severity-label report))))
    (make-adapter-anomaly-result
     :primary-adapter (adapter-anomaly-snapshot-adapter-id current)
     :secondary-adapter (adapter-anomaly-snapshot-adapter-id baseline)
     :report report
     :divergence-findings divergence
     :anomaly-count count
     :risk-score risk
     :severity-label severity)))

(defun snapshot->json (snapshot)
  "Serialize adapter-anomaly-snapshot to deterministic JSON."
  (declare (type adapter-anomaly-snapshot snapshot)
           (optimize (safety 3)))
  (format nil
          "{\"adapter_id\":\"~A\",\"session_count\":~D,\"usage_count\":~D}"
          (adapter-anomaly-snapshot-adapter-id snapshot)
          (adapter-anomaly-snapshot-session-count snapshot)
          (length (adapter-anomaly-snapshot-usage-records snapshot))))

(defun anomaly-result->json (result)
  "Serialize adapter-anomaly-result to deterministic JSON.
   Focuses on alert-ready scalar fields."
  (declare (type adapter-anomaly-result result)
           (optimize (safety 3)))
  (format nil
          "{\"primary\":\"~A\",\"secondary\":\"~A\",\"severity\":\"~(~A~)\",\"anomaly_count\":~D,\"risk_score\":~D,\"divergence_count\":~D}"
          (adapter-anomaly-result-primary-adapter result)
          (adapter-anomaly-result-secondary-adapter result)
          (adapter-anomaly-result-severity-label result)
          (adapter-anomaly-result-anomaly-count result)
          (adapter-anomaly-result-risk-score result)
          (orrery/coalton/core:cl-finding-list-count
           (adapter-anomaly-result-divergence-findings result))))
