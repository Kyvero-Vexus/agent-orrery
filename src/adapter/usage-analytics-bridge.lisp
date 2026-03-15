;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; usage-analytics-bridge.lisp — CL bridge for Coalton usage analytics

(in-package #:orrery/adapter)

(declaim (ftype (function (orrery/domain:usage-record)
                          (values t &optional))
                usage-record->coalton-entry))
(defun usage-record->coalton-entry (record)
  "Convert domain usage-record to Coalton UsageEntry. Pure."
  (declare (optimize (safety 3)))
  (orrery/coalton/core:cl-make-usage-entry
   (orrery/domain:ur-model record)
   (orrery/domain:ur-prompt-tokens record)
   (orrery/domain:ur-completion-tokens record)
   (orrery/domain:ur-timestamp record)))

(declaim (ftype (function (list string) (values t &optional))
                usage-records->coalton-bucket))
(defun usage-records->coalton-bucket (records period-label)
  "Convert list of usage-records to Coalton UsageBucket. Pure."
  (declare (optimize (safety 3)))
  (let ((entries (mapcar #'usage-record->coalton-entry records)))
    (orrery/coalton/core:cl-aggregate-entries period-label entries)))

(declaim (ftype (function (t) (values string &optional))
                coalton-summary->json))
(defun coalton-summary->json (summary)
  "Serialize Coalton UsageSummary to deterministic JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"total_tokens\":~D,\"total_cost_cents\":~D}"
          (orrery/coalton/core:cl-summary-total-tokens summary)
          (orrery/coalton/core:cl-summary-total-cost summary)))
