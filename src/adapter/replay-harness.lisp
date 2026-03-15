;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; replay-harness.lisp — Deterministic fixture/live replay for S1 gate diagnostics
;;;
;;; Replays recorded adapter event streams through the decision pipeline
;;; to produce verifiable, deterministic gate decisions for debugging.

(in-package #:orrery/adapter)

;;; ─── Replay Event ───

(deftype replay-event-type ()
  "Categories of replayable events."
  '(member :session :cron :health :usage :event :alert :probe))

(deftype replay-source ()
  "Origin of a replay stream."
  '(member :fixture :live :synthetic))

(defstruct (replay-event
             (:constructor make-replay-event
                 (&key sequence-id event-type payload timestamp))
             (:conc-name re-))
  "One recorded event in a replay stream."
  (sequence-id 0 :type (integer 0))
  (event-type :event :type replay-event-type)
  (payload "" :type string)
  (timestamp 0 :type (integer 0)))

;;; ─── Replay Stream ───

(defstruct (replay-stream
             (:constructor make-replay-stream
                 (&key stream-id source events seed metadata))
             (:conc-name rstr-))
  "Ordered sequence of events for deterministic replay."
  (stream-id "" :type string)
  (source :fixture :type replay-source)
  (events '() :type list)
  (seed 0 :type (integer 0))
  (metadata "" :type string))

;;; ─── Replay Diff ───

(deftype diff-kind ()
  "Category of difference between original and replayed."
  '(member :verdict-mismatch :score-mismatch :finding-count-mismatch :identical))

(defstruct (replay-diff
             (:constructor make-replay-diff
                 (&key event-id diff-kind original-value replayed-value description))
             (:conc-name rd-))
  "One difference between original and replayed decision."
  (event-id 0 :type (integer 0))
  (diff-kind :identical :type diff-kind)
  (original-value "" :type string)
  (replayed-value "" :type string)
  (description "" :type string))

;;; ─── Replay Result ───

(defstruct (replay-report
             (:constructor make-replay-report
                 (&key stream-id decisions match-p diff-count diffs elapsed-ms))
             (:conc-name rpt-))
  "Result of replaying a stream through the decision pipeline."
  (stream-id "" :type string)
  (decisions '() :type list)
  (match-p t :type boolean)
  (diff-count 0 :type (integer 0))
  (diffs '() :type list)
  (elapsed-ms 0 :type (integer 0)))

;;; ─── Event Ordering Validation ───

(declaim (ftype (function (list) (values boolean string &optional))
                validate-ordering))
(defun validate-ordering (events)
  "Verify events are monotonically ordered by sequence-id.
   Returns (VALUES valid-p message)."
  (declare (optimize (safety 3)))
  (if (or (null events) (null (cdr events)))
      (values t "Ordering valid")
      (loop for prev = (first events) then curr
            for curr in (rest events)
            when (>= (re-sequence-id prev) (re-sequence-id curr))
              do (return (values nil
                                 (format nil "Non-monotonic: seq ~D >= ~D"
                                         (re-sequence-id prev)
                                         (re-sequence-id curr))))
            finally (return (values t "Ordering valid")))))

;;; ─── Event → Probe Finding Conversion ───

(declaim (ftype (function (replay-event) probe-finding)
                event-to-finding))
(defun event-to-finding (event)
  "Convert a replay event to a probe finding for decision pipeline input.
   Maps event-type to probe-domain deterministically."
  (declare (optimize (safety 3)))
  (let ((domain (ecase (re-event-type event)
                  (:session :runtime)
                  (:cron :runtime)
                  (:health :transport)
                  (:usage :capability)
                  (:event :conformance)
                  (:alert :auth)
                  (:probe :schema))))
    (make-probe-finding
     :domain domain
     :status (if (string= (re-payload event) "")
                 :unknown
                 :healthy)
     :severity (if (string= (re-payload event) "") 50 0)
     :message (re-payload event)
     :evidence-ref (format nil "replay:~D" (re-sequence-id event)))))

;;; ─── Replay Engine ───

(declaim (ftype (function (replay-stream &key (:thresholds severity-thresholds))
                          decision-record)
                replay-to-decision))
(defun replay-to-decision (stream &key (thresholds (make-severity-thresholds)))
  "Replay a stream's events through the decision pipeline.
   Returns the decision-record for the full stream."
  (declare (optimize (safety 3)))
  (let ((findings (mapcar #'event-to-finding (rstr-events stream))))
    (run-decision-pipeline findings
                           :thresholds thresholds
                           :timestamp (rstr-seed stream))))

;;; ─── Diff Analyzer ───

(declaim (ftype (function (decision-record decision-record (integer 0)) list)
                diff-decisions))
(defun diff-decisions (original replayed event-id)
  "Compare two decision records and return list of diffs."
  (declare (optimize (safety 3)))
  (let ((diffs '()))
    (unless (eq (dec-verdict original) (dec-verdict replayed))
      (push (make-replay-diff
             :event-id event-id
             :diff-kind :verdict-mismatch
             :original-value (symbol-name (dec-verdict original))
             :replayed-value (symbol-name (dec-verdict replayed))
             :description "Verdict changed between recordings")
            diffs))
    (unless (= (dec-aggregate-score original) (dec-aggregate-score replayed))
      (push (make-replay-diff
             :event-id event-id
             :diff-kind :score-mismatch
             :original-value (format nil "~D" (dec-aggregate-score original))
             :replayed-value (format nil "~D" (dec-aggregate-score replayed))
             :description "Aggregate score changed")
            diffs))
    (unless (= (dec-finding-count original) (dec-finding-count replayed))
      (push (make-replay-diff
             :event-id event-id
             :diff-kind :finding-count-mismatch
             :original-value (format nil "~D" (dec-finding-count original))
             :replayed-value (format nil "~D" (dec-finding-count replayed))
             :description "Finding count changed")
            diffs))
    (nreverse diffs)))

;;; ─── Full Replay Pipeline ───

(declaim (ftype (function (replay-stream decision-record
                           &key (:thresholds severity-thresholds))
                          replay-report)
                run-replay))
(defun run-replay (stream original-decision &key (thresholds (make-severity-thresholds)))
  "Run full replay and compare with original decision.
   Pure function: deterministic given same inputs."
  (declare (optimize (safety 3)))
  (let* ((replayed (replay-to-decision stream :thresholds thresholds))
         (diffs (diff-decisions original-decision replayed 0))
         (match (null diffs)))
    (make-replay-report
     :stream-id (rstr-stream-id stream)
     :decisions (list replayed)
     :match-p match
     :diff-count (length diffs)
     :diffs diffs
     :elapsed-ms 0)))

;;; ─── Batch Replay ───

(declaim (ftype (function (list list &key (:thresholds severity-thresholds))
                          list)
                run-batch-replay))
(defun run-batch-replay (streams original-decisions &key (thresholds (make-severity-thresholds)))
  "Replay multiple streams against original decisions.
   Returns list of replay-reports."
  (declare (optimize (safety 3)))
  (mapcar (lambda (stream orig)
            (run-replay stream orig :thresholds thresholds))
          streams original-decisions))
