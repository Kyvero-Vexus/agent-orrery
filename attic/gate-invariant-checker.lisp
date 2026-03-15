;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-invariant-checker.lisp — Validates replay/schema artifacts against S1 gate contracts
;;;
;;; Pure, typed invariant checker: event ordering, snapshot monotonicity,
;;; decision determinism, schema contract compliance.

(in-package #:orrery/adapter)

;;; ─── Invariant Classification ───

(deftype invariant-class ()
  "Category of gate invariant."
  '(member :ordering :monotonicity :determinism :schema-contract))

(deftype violation-severity ()
  "Severity of an invariant violation."
  '(member :warning :error :fatal))

;;; ─── Invariant Violation ───

(defstruct (invariant-violation
             (:constructor make-invariant-violation
                 (&key invariant-class severity description artifact-ref evidence))
             (:conc-name iv-))
  "One invariant violation found during checking."
  (invariant-class :ordering :type invariant-class)
  (severity :error :type violation-severity)
  (description "" :type string)
  (artifact-ref "" :type string)
  (evidence "" :type string))

;;; ─── Invariant Report ───

(defstruct (invariant-report
             (:constructor make-invariant-report
                 (&key pass-p violation-count violations checked-count summary))
             (:conc-name ir-))
  "Aggregate result of running an invariant suite."
  (pass-p t :type boolean)
  (violation-count 0 :type (integer 0))
  (violations '() :type list)
  (checked-count 0 :type (integer 0))
  (summary "" :type string))

;;; ─── Event Ordering Invariant ───

(declaim (ftype (function (list) list) check-ordering-invariant))
(defun check-ordering-invariant (replay-streams)
  "Check that every replay-stream has monotonically increasing sequence-ids.
   Returns list of invariant-violation (empty if all pass)."
  (declare (optimize (safety 3)))
  (let ((violations '()))
    (dolist (stream replay-streams)
      (multiple-value-bind (ok msg)
          (validate-ordering (rstr-events stream))
        (unless ok
          (push (make-invariant-violation
                 :invariant-class :ordering
                 :severity :fatal
                 :description msg
                 :artifact-ref (rstr-stream-id stream)
                 :evidence (format nil "stream=~A events=~D"
                                   (rstr-stream-id stream)
                                   (length (rstr-events stream))))
                violations))))
    (nreverse violations)))

;;; ─── Snapshot Monotonicity Invariant ───

(declaim (ftype (function (list) list) check-monotonicity-invariant))
(defun check-monotonicity-invariant (snapshots)
  "Check that normalized-snapshot sync-tokens are non-decreasing.
   SNAPSHOTS is a list of (cons string-sync-token string-label) pairs,
   or normalized-snapshot structs (using normalized-snapshot-sync-token accessor).
   Returns list of invariant-violation."
  (declare (optimize (safety 3)))
  (if (or (null snapshots) (null (cdr snapshots)))
      '()
      (let ((violations '())
            (idx 0))
        (loop for prev = (first snapshots) then curr
              for curr in (rest snapshots)
              do (let ((prev-token (snapshot-sync-token prev))
                       (curr-token (snapshot-sync-token curr)))
                   (incf idx)
                   (when (and (string/= prev-token "")
                              (string/= curr-token "")
                              (string> prev-token curr-token))
                     (push (make-invariant-violation
                            :invariant-class :monotonicity
                            :severity :error
                            :description (format nil "Sync-token decreased at position ~D: ~S > ~S"
                                                 idx prev-token curr-token)
                            :artifact-ref (format nil "snapshot-pair:~D" idx)
                            :evidence (format nil "prev=~S curr=~S" prev-token curr-token))
                           violations))))
        (nreverse violations))))

(declaim (ftype (function (t) string) snapshot-sync-token))
(defun snapshot-sync-token (snapshot)
  "Extract sync-token from a snapshot. Accepts normalized-snapshot structs or (cons token label).
   For normalized-snapshot structs, uses the exported accessor from orrery/pipeline."
  (declare (optimize (safety 3)))
  (etypecase snapshot
    (cons (the string (car snapshot)))
    (orrery/pipeline:normalized-snapshot
     (the string (orrery/pipeline:normalized-snapshot-sync-token snapshot)))))

;;; ─── Decision Determinism Invariant ───

(declaim (ftype (function (list list &key (:thresholds severity-thresholds)) list)
                check-determinism-invariant))
(defun check-determinism-invariant (streams reports &key (thresholds (make-severity-thresholds)))
  "Check that replaying each stream produces the same decision as its report.
   STREAMS and REPORTS must be parallel lists.
   Returns list of invariant-violation."
  (declare (optimize (safety 3)))
  (let ((violations '()))
    (loop for stream in streams
          for report in reports
          do (let* ((replayed (replay-to-decision stream :thresholds thresholds))
                    (original (first (rpt-decisions report))))
               (when original
                 (unless (and (eq (dec-verdict replayed) (dec-verdict original))
                              (= (dec-aggregate-score replayed) (dec-aggregate-score original))
                              (= (dec-finding-count replayed) (dec-finding-count original)))
                   (push (make-invariant-violation
                          :invariant-class :determinism
                          :severity :fatal
                          :description (format nil "Replay non-deterministic for stream ~A: ~
                                                    original=~A/~D replayed=~A/~D"
                                               (rstr-stream-id stream)
                                               (dec-verdict original)
                                               (dec-aggregate-score original)
                                               (dec-verdict replayed)
                                               (dec-aggregate-score replayed))
                          :artifact-ref (rstr-stream-id stream)
                          :evidence (format nil "orig-verdict=~A orig-score=~D ~
                                                 replay-verdict=~A replay-score=~D"
                                            (dec-verdict original)
                                            (dec-aggregate-score original)
                                            (dec-verdict replayed)
                                            (dec-aggregate-score replayed)))
                         violations)))))
    (nreverse violations)))

;;; ─── Schema Contract Invariant ───

(declaim (ftype (function (list) list) check-schema-contract-invariant))
(defun check-schema-contract-invariant (compat-reports)
  "Check that no compat-report has :breaking severity.
   :degrading mismatches produce :warning violations.
   Returns list of invariant-violation."
  (declare (optimize (safety 3)))
  (let ((violations '()))
    (dolist (report compat-reports)
      (let ((sev (cr-max-severity report))
            (endpoint (cr-endpoint report)))
        (ecase sev
          (:breaking
           (push (make-invariant-violation
                  :invariant-class :schema-contract
                  :severity :error
                  :description (format nil "Breaking schema mismatch on endpoint ~A (~D mismatches)"
                                       endpoint (length (cr-mismatches report)))
                  :artifact-ref endpoint
                  :evidence (format nil "compatible-p=~A mismatches=~D"
                                    (cr-compatible-p report)
                                    (length (cr-mismatches report))))
                 violations))
          (:degrading
           (push (make-invariant-violation
                  :invariant-class :schema-contract
                  :severity :warning
                  :description (format nil "Degrading schema mismatch on endpoint ~A (~D mismatches)"
                                       endpoint (length (cr-mismatches report)))
                  :artifact-ref endpoint
                  :evidence (format nil "compatible-p=~A mismatches=~D"
                                    (cr-compatible-p report)
                                    (length (cr-mismatches report))))
                 violations))
          (:info nil))))
    (nreverse violations)))

;;; ─── Has-Fatal Predicate ───

(declaim (ftype (function (list) boolean) has-fatal-violation-p))
(defun has-fatal-violation-p (violations)
  "Return T if any violation has :fatal severity."
  (declare (optimize (safety 3)))
  (some (lambda (v) (eq (iv-severity v) :fatal)) violations))

;;; ─── Suite Runner ───

(declaim (ftype (function (list list list list
                           &key (:thresholds severity-thresholds))
                          invariant-report)
                run-invariant-suite))
(defun run-invariant-suite (streams snapshots reports compat-reports
                            &key (thresholds (make-severity-thresholds)))
  "Run all gate invariants and aggregate into a single report.
   STREAMS: list of replay-stream
   SNAPSHOTS: list of normalized-snapshot or (cons token label)
   REPORTS: list of replay-report (parallel to STREAMS)
   COMPAT-REPORTS: list of compat-report
   Pure function."
  (declare (optimize (safety 3)))
  (let* ((ordering-vs (check-ordering-invariant streams))
         (mono-vs (check-monotonicity-invariant snapshots))
         (det-vs (check-determinism-invariant streams reports :thresholds thresholds))
         (schema-vs (check-schema-contract-invariant compat-reports))
         (all-vs (append ordering-vs mono-vs det-vs schema-vs))
         (checked (+ (length streams)      ; ordering checks
                     (max 0 (1- (length snapshots))) ; monotonicity pairs
                     (length streams)      ; determinism checks
                     (length compat-reports))) ; schema checks
         (pass (null all-vs)))
    (make-invariant-report
     :pass-p pass
     :violation-count (length all-vs)
     :violations all-vs
     :checked-count checked
     :summary (format nil "~D/~D checks passed~@[; ~D violations (~{~A~^, ~})~]"
                      (- checked (length all-vs)) checked
                      (when all-vs (length all-vs))
                      (when all-vs
                        (remove-duplicates
                         (mapcar (lambda (v) (symbol-name (iv-invariant-class v)))
                                 all-vs)
                         :test #'string=))))))
