;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; decision-audit.lisp — Gate decision audit log with deterministic serialization
;;;
;;; Typed audit trail for gate verdicts. Pure, append-only, ordered.

(in-package #:orrery/adapter)

;;; ─── Audit Entry ───

(defstruct (audit-entry
             (:constructor make-audit-entry
                 (&key entry-id verdict aggregate-score finding-count
                       evidence-ref gate-id context timestamp))
             (:conc-name aue-))
  "Single gate decision audit record."
  (entry-id "" :type string)
  (verdict :pass :type keyword)
  (aggregate-score 0 :type (integer 0))
  (finding-count 0 :type (integer 0))
  (evidence-ref "" :type string)
  (gate-id "" :type string)
  (context "" :type string)
  (timestamp 0 :type (integer 0)))

;;; ─── Audit Log ───

(defstruct (audit-log
             (:constructor make-audit-log
                 (&key log-id entries entry-count
                       pass-count fail-count escalate-count
                       first-timestamp last-timestamp))
             (:conc-name al-))
  "Ordered audit trail of gate decisions."
  (log-id "" :type string)
  (entries '() :type list)
  (entry-count 0 :type (integer 0))
  (pass-count 0 :type (integer 0))
  (fail-count 0 :type (integer 0))
  (escalate-count 0 :type (integer 0))
  (first-timestamp 0 :type (integer 0))
  (last-timestamp 0 :type (integer 0)))

;;; ─── Audit Diff ───

(deftype diff-kind ()
  '(member :added :removed :changed :unchanged))

(defstruct (audit-diff-entry
             (:constructor make-audit-diff-entry
                 (&key entry-id kind old-verdict new-verdict detail))
             (:conc-name ade-))
  "One diff item between two audit logs."
  (entry-id "" :type string)
  (kind :unchanged :type diff-kind)
  (old-verdict nil :type (or null keyword))
  (new-verdict nil :type (or null keyword))
  (detail "" :type string))

(defstruct (audit-diff
             (:constructor make-audit-diff
                 (&key diff-id base-log-id target-log-id
                       entries added-count removed-count changed-count
                       regressions-p))
             (:conc-name ad-))
  "Comparison between two audit logs."
  (diff-id "" :type string)
  (base-log-id "" :type string)
  (target-log-id "" :type string)
  (entries '() :type list)
  (added-count 0 :type (integer 0))
  (removed-count 0 :type (integer 0))
  (changed-count 0 :type (integer 0))
  (regressions-p nil :type boolean))

;;; ─── Entry from Decision Record ───

(declaim (ftype (function (decision-record &key (:evidence-ref string)
                                               (:gate-id string)
                                               (:context string)
                                               (:timestamp (integer 0)))
                          (values audit-entry &optional))
                make-audit-entry-from-decision))
(defun make-audit-entry-from-decision (record &key (evidence-ref "")
                                                    (gate-id "")
                                                    (context "")
                                                    (timestamp 0))
  "Convert a decision-record into an audit-entry. Pure."
  (declare (optimize (safety 3)))
  (make-audit-entry
   :entry-id (format nil "ae-~A-~D" (dec-verdict record) timestamp)
   :verdict (dec-verdict record)
   :aggregate-score (dec-aggregate-score record)
   :finding-count (dec-finding-count record)
   :evidence-ref evidence-ref
   :gate-id gate-id
   :context context
   :timestamp timestamp))

;;; ─── Append ───

(declaim (ftype (function (audit-log audit-entry) (values audit-log &optional))
                append-to-audit-log))
(defun append-to-audit-log (log entry)
  "Append entry to log, returning new log. Pure (no mutation)."
  (declare (optimize (safety 3)))
  (let* ((new-entries (append (al-entries log) (list entry)))
         (count (1+ (al-entry-count log)))
         (pass-delta (if (eq :pass (aue-verdict entry)) 1 0))
         (fail-delta (if (member (aue-verdict entry) '(:fail :blocked-contract)) 1 0))
         (esc-delta (if (eq :escalate (aue-verdict entry)) 1 0)))
    (make-audit-log
     :log-id (al-log-id log)
     :entries new-entries
     :entry-count count
     :pass-count (+ (al-pass-count log) pass-delta)
     :fail-count (+ (al-fail-count log) fail-delta)
     :escalate-count (+ (al-escalate-count log) esc-delta)
     :first-timestamp (if (zerop (al-first-timestamp log))
                          (aue-timestamp entry)
                          (al-first-timestamp log))
     :last-timestamp (aue-timestamp entry))))

;;; ─── Build Log ───

(declaim (ftype (function (list &key (:log-id string)) (values audit-log &optional))
                build-audit-log))
(defun build-audit-log (decision-records &key (log-id ""))
  "Build an audit-log from a list of decision-records. Pure."
  (declare (optimize (safety 3)))
  (let ((log (make-audit-log :log-id log-id)))
    (dolist (rec decision-records)
      (setf log (append-to-audit-log log (make-audit-entry-from-decision rec))))
    log))

;;; ─── Diff ───

(declaim (ftype (function (audit-log audit-log &key (:diff-id string))
                          (values audit-diff &optional))
                diff-audit-logs))
(defun diff-audit-logs (base-log target-log &key (diff-id ""))
  "Compare two audit logs entry by entry. Pure."
  (declare (optimize (safety 3)))
  (let ((base-map (make-hash-table :test 'equal))
        (target-map (make-hash-table :test 'equal))
        (diff-entries '())
        (added 0) (removed 0) (changed 0) (regressions nil))
    ;; Index base
    (dolist (e (al-entries base-log))
      (setf (gethash (aue-entry-id e) base-map) e))
    ;; Index target
    (dolist (e (al-entries target-log))
      (setf (gethash (aue-entry-id e) target-map) e))
    ;; Find added and changed
    (dolist (e (al-entries target-log))
      (let ((base-entry (gethash (aue-entry-id e) base-map)))
        (cond
          ((null base-entry)
           (push (make-audit-diff-entry :entry-id (aue-entry-id e)
                                        :kind :added
                                        :new-verdict (aue-verdict e)
                                        :detail "New entry")
                 diff-entries)
           (incf added))
          ((not (eq (aue-verdict base-entry) (aue-verdict e)))
           (push (make-audit-diff-entry :entry-id (aue-entry-id e)
                                        :kind :changed
                                        :old-verdict (aue-verdict base-entry)
                                        :new-verdict (aue-verdict e)
                                        :detail (format nil "~A → ~A"
                                                        (aue-verdict base-entry) (aue-verdict e)))
                 diff-entries)
           (incf changed)
           ;; Regression: was pass, now fail/escalate
           (when (and (eq :pass (aue-verdict base-entry))
                      (not (eq :pass (aue-verdict e))))
             (setf regressions t))))))
    ;; Find removed
    (dolist (e (al-entries base-log))
      (unless (gethash (aue-entry-id e) target-map)
        (push (make-audit-diff-entry :entry-id (aue-entry-id e)
                                     :kind :removed
                                     :old-verdict (aue-verdict e)
                                     :detail "Removed")
              diff-entries)
        (incf removed)))
    (make-audit-diff
     :diff-id diff-id
     :base-log-id (al-log-id base-log)
     :target-log-id (al-log-id target-log)
     :entries (nreverse diff-entries)
     :added-count added
     :removed-count removed
     :changed-count changed
     :regressions-p regressions)))

;;; ─── JSON Serialization ───

(declaim (ftype (function (audit-entry) (values string &optional))
                audit-entry-to-json))
(defun audit-entry-to-json (entry)
  "Deterministic JSON for one audit entry. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"entry_id\":\"~A\",\"verdict\":\"~A\",\"aggregate_score\":~D,~
               \"finding_count\":~D,\"evidence_ref\":\"~A\",\"gate_id\":\"~A\",~
               \"context\":\"~A\",\"timestamp\":~D}"
          (aue-entry-id entry) (aue-verdict entry) (aue-aggregate-score entry)
          (aue-finding-count entry) (aue-evidence-ref entry) (aue-gate-id entry)
          (aue-context entry) (aue-timestamp entry)))

(declaim (ftype (function (audit-log) (values string &optional))
                audit-log-to-json))
(defun audit-log-to-json (log)
  "Deterministic JSON for audit log. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"log_id\":\"~A\",\"entry_count\":~D,\"pass_count\":~D,~
               \"fail_count\":~D,\"escalate_count\":~D,~
               \"first_timestamp\":~D,\"last_timestamp\":~D,~
               \"entries\":[~{~A~^,~}]}"
          (al-log-id log) (al-entry-count log) (al-pass-count log)
          (al-fail-count log) (al-escalate-count log)
          (al-first-timestamp log) (al-last-timestamp log)
          (mapcar #'audit-entry-to-json (al-entries log))))

(declaim (ftype (function (audit-diff) (values string &optional))
                audit-diff-to-json))
(defun audit-diff-to-json (diff)
  "Deterministic JSON for audit diff. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"diff_id\":\"~A\",\"base_log_id\":\"~A\",\"target_log_id\":\"~A\",~
               \"added_count\":~D,\"removed_count\":~D,\"changed_count\":~D,~
               \"regressions\":~A}"
          (ad-diff-id diff) (ad-base-log-id diff) (ad-target-log-id diff)
          (ad-added-count diff) (ad-removed-count diff) (ad-changed-count diff)
          (if (ad-regressions-p diff) "true" "false")))
