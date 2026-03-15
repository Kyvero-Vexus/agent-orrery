;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-invariant.lisp — S1 gate-invariant checker
;;;
;;; Validates replay outputs and schema corpora against gate contracts:
;;; ordering, determinism, schema coverage, decision consistency.

(in-package #:orrery/adapter)

;;; ─── Invariant Types ───

(deftype invariant-category ()
  "Categories of gate invariants."
  '(member :ordering :determinism :schema-coverage :decision-consistency))

(deftype violation-severity ()
  "Severity of an invariant violation."
  '(member :critical :warning :info))

(defstruct (invariant-violation
             (:constructor make-invariant-violation
                 (&key category severity description evidence))
             (:conc-name iv-))
  "One invariant violation."
  (category :ordering :type invariant-category)
  (severity :critical :type violation-severity)
  (description "" :type string)
  (evidence "" :type string))

(defstruct (invariant-report
             (:constructor make-invariant-report
                 (&key pass-p violations checked-count pass-count
                       fail-count timestamp))
             (:conc-name ir-))
  "Aggregate invariant check report."
  (pass-p t :type boolean)
  (violations '() :type list)
  (checked-count 0 :type (integer 0))
  (pass-count 0 :type (integer 0))
  (fail-count 0 :type (integer 0))
  (timestamp 0 :type (integer 0)))

;;; ─── Ordering Invariant ───

(declaim (ftype (function (list) list) check-ordering-invariant))
(defun check-ordering-invariant (events)
  "Check that replay events have strictly monotonic sequence-ids.
   Returns list of violations (empty if valid)."
  (declare (optimize (safety 3)))
  (let ((violations '()))
    (when (and events (cdr events))
      (loop for prev = (first events) then curr
            for curr in (rest events)
            when (>= (re-sequence-id prev) (re-sequence-id curr))
              do (push (make-invariant-violation
                        :category :ordering
                        :severity :critical
                        :description (format nil "Non-monotonic: seq ~D >= ~D"
                                             (re-sequence-id prev)
                                             (re-sequence-id curr))
                        :evidence (format nil "events[~D,~D]"
                                          (re-sequence-id prev)
                                          (re-sequence-id curr)))
                       violations)))
    (nreverse violations)))

;;; ─── Determinism Invariant ───

(declaim (ftype (function (replay-stream severity-thresholds) list)
                check-determinism-invariant))
(defun check-determinism-invariant (stream thresholds)
  "Check that replaying the same stream twice yields identical decisions.
   Returns list of violations (empty if deterministic)."
  (declare (optimize (safety 3)))
  (let* ((d1 (replay-to-decision stream :thresholds thresholds))
         (d2 (replay-to-decision stream :thresholds thresholds))
         (violations '()))
    (unless (eq (dec-verdict d1) (dec-verdict d2))
      (push (make-invariant-violation
             :category :determinism
             :severity :critical
             :description (format nil "Non-deterministic verdict: ~A vs ~A"
                                  (dec-verdict d1) (dec-verdict d2))
             :evidence (format nil "stream:~A seed:~D"
                               (rstr-stream-id stream) (rstr-seed stream)))
            violations))
    (unless (= (dec-aggregate-score d1) (dec-aggregate-score d2))
      (push (make-invariant-violation
             :category :determinism
             :severity :critical
             :description (format nil "Non-deterministic score: ~D vs ~D"
                                  (dec-aggregate-score d1) (dec-aggregate-score d2))
             :evidence (format nil "stream:~A" (rstr-stream-id stream)))
            violations))
    (nreverse violations)))

;;; ─── Schema Coverage Invariant ───

(declaim (ftype (function (compat-report) list) check-schema-coverage-invariant))
(defun check-schema-coverage-invariant (report)
  "Check that all fixture fields are present in live schema.
   Returns list of violations for missing required fields."
  (declare (optimize (safety 3)))
  (let ((violations '()))
    (dolist (mm (cr-mismatches report))
      (when (and (eq (cm-category mm) :missing-field)
                 (eq (cm-severity mm) :breaking))
        (push (make-invariant-violation
               :category :schema-coverage
               :severity :critical
               :description (format nil "Required field missing: ~A" (cm-path mm))
               :evidence (format nil "endpoint:~A" (cr-endpoint report)))
              violations)))
    (nreverse violations)))

;;; ─── Decision Consistency Invariant ───

(declaim (ftype (function (decision-record severity-thresholds) list)
                check-decision-consistency-invariant))
(defun check-decision-consistency-invariant (record thresholds)
  "Check that the decision's verdict is consistent with its scores and thresholds."
  (declare (optimize (safety 3)))
  (let ((violations '())
        (mean (dec-aggregate-score record))
        (max-sev (dec-max-severity record))
        (verdict (dec-verdict record)))
    ;; If max > 80 then verdict must be :fail
    (when (and (> max-sev 80) (not (eq verdict :fail)))
      (push (make-invariant-violation
             :category :decision-consistency
             :severity :critical
             :description (format nil "Max severity ~D > 80 but verdict is ~A (should be :fail)"
                                  max-sev verdict)
             :evidence (format nil "score:~D/~D" mean max-sev))
            violations))
    ;; If mean <= pass-ceiling and max <= 80, verdict should be :pass
    (when (and (<= mean (st-pass-ceiling thresholds))
               (<= max-sev 80)
               (not (eq verdict :pass)))
      (push (make-invariant-violation
             :category :decision-consistency
             :severity :warning
             :description (format nil "Mean ~D <= ~D but verdict is ~A (expected :pass)"
                                  mean (st-pass-ceiling thresholds) verdict)
             :evidence (format nil "score:~D/~D" mean max-sev))
            violations))
    ;; If mean > degraded-ceiling, verdict should be :fail (unless max > 80 already caught)
    (when (and (> mean (st-degraded-ceiling thresholds))
               (<= max-sev 80)
               (not (eq verdict :fail)))
      (push (make-invariant-violation
             :category :decision-consistency
             :severity :critical
             :description (format nil "Mean ~D > ~D but verdict is ~A (should be :fail)"
                                  mean (st-degraded-ceiling thresholds) verdict)
             :evidence (format nil "score:~D/~D" mean max-sev))
            violations))
    (nreverse violations)))

;;; ─── Report Builder ───

(declaim (ftype (function (list &key (:timestamp (integer 0))) invariant-report)
                build-invariant-report))
(defun build-invariant-report (all-violations &key (timestamp 0))
  "Build aggregate report from all invariant violations."
  (declare (optimize (safety 3)))
  (let* ((critical-count (count :critical all-violations :key #'iv-severity))
         (total (length all-violations))
         (pass (zerop critical-count)))
    (make-invariant-report
     :pass-p pass
     :violations all-violations
     :checked-count total
     :pass-count (- total critical-count)
     :fail-count critical-count
     :timestamp timestamp)))

;;; ─── Full Invariant Suite ───

(declaim (ftype (function (replay-stream decision-record compat-report
                           &key (:thresholds severity-thresholds)
                                (:timestamp (integer 0)))
                          invariant-report)
                run-invariant-suite))
(defun run-invariant-suite (stream decision compat-report
                            &key (thresholds (make-severity-thresholds))
                                 (timestamp 0))
  "Run all gate invariants and produce aggregate report."
  (declare (optimize (safety 3)))
  (let ((all-violations '()))
    ;; 1. Ordering
    (setf all-violations
          (nconc all-violations (check-ordering-invariant (rstr-events stream))))
    ;; 2. Determinism
    (setf all-violations
          (nconc all-violations (check-determinism-invariant stream thresholds)))
    ;; 3. Schema coverage
    (setf all-violations
          (nconc all-violations (check-schema-coverage-invariant compat-report)))
    ;; 4. Decision consistency
    (setf all-violations
          (nconc all-violations
                 (check-decision-consistency-invariant decision thresholds)))
    (build-invariant-report all-violations :timestamp timestamp)))
