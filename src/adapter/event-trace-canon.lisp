;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; event-trace-canon.lisp — Cross-UI event trace canonicalization
;;;
;;; Converts adapter/runtime events into canonical trace schema
;;; with stable ordering, IDs, and diff semantics.

(in-package #:orrery/adapter)

;;; ─── Types ───

(deftype event-kind ()
  '(member :session :cron :health :alert :usage :probe :lifecycle))

(deftype source-tag ()
  '(member :adapter :pipeline :store :harness))

(defstruct (trace-event (:conc-name tev-))
  "Canonical event in the trace stream."
  (seq-id         0 :type fixnum)
  (timestamp      0 :type fixnum)
  (source-tag :adapter :type source-tag)
  (event-kind :session :type event-kind)
  (payload-hash   0 :type fixnum))

(defstruct (trace-stream (:conc-name ts-))
  "Ordered sequence of canonical trace events."
  (events nil :type list)
  (count    0 :type fixnum))

(defstruct (trace-diff-result (:conc-name tdr-))
  "Result of diffing two trace streams."
  (matched-count   0 :type fixnum)
  (mismatched-count 0 :type fixnum)
  (missing-left    0 :type fixnum)
  (missing-right   0 :type fixnum)
  (details        nil :type list))

;;; ─── Deterministic ID ───

(declaim (ftype (function (source-tag event-kind fixnum fixnum)
                          (values fixnum &optional))
                computev-seq-id))
(defun computev-seq-id (source event-k ts payload-h)
  "Deterministic sequence ID from event components."
  (declare (optimize (safety 3)))
  (logand (sxhash (list source event-k ts payload-h))
          most-positive-fixnum))

;;; ─── Payload Hash ───

(declaim (ftype (function (string) (values fixnum &optional))
                simple-payload-hash))
(defun simple-payload-hash (payload-str)
  "Simple deterministic hash of a payload string."
  (declare (optimize (safety 3)))
  (logand (sxhash payload-str) most-positive-fixnum))

;;; ─── Canonicalize Single Event ───

(declaim (ftype (function (source-tag event-kind fixnum string)
                          (values trace-event &optional))
                canonicalize-event))
(defun canonicalize-event (source event-k timestamp payload-str)
  "Create canonical trace-event from components. Pure."
  (declare (optimize (safety 3)))
  (let ((ph (simple-payload-hash payload-str)))
    (make-trace-event
     :seq-id (computev-seq-id source event-k timestamp ph)
     :timestamp timestamp
     :source-tag source
     :event-kind event-k
     :payload-hash ph)))

;;; ─── Ordering ───

(declaim (ftype (function (trace-event trace-event)
                          (values boolean &optional))
                trace-event< ))
(defun trace-event< (a b)
  "Compare trace events by (timestamp, seq-id). Pure."
  (declare (optimize (safety 3)))
  (or (< (tev-timestamp a) (tev-timestamp b))
      (and (= (tev-timestamp a) (tev-timestamp b))
           (< (tev-seq-id a) (tev-seq-id b)))))

;;; ─── Dedup by seq-id ───

(declaim (ftype (function (list) (values list &optional))
                dedup-by-seq-id))
(defun dedup-by-seq-id (sorted-events)
  "Remove duplicate seq-ids from sorted event list. Pure."
  (declare (optimize (safety 3)))
  (if (null sorted-events)
      nil
      (let ((result (list (first sorted-events))))
        (loop :for ev :in (rest sorted-events)
              :unless (= (tev-seq-id ev) (tev-seq-id (first result)))
                :do (push ev result))
        (nreverse result))))

;;; ─── Canonicalize Stream ───

(declaim (ftype (function (list) (values trace-stream &optional))
                canonicalize-stream))
(defun canonicalize-stream (events)
  "Sort and dedup events into a canonical trace-stream. Pure."
  (declare (optimize (safety 3)))
  (let* ((sorted (sort (copy-list events) #'trace-event<))
         (deduped (dedup-by-seq-id sorted)))
    (make-trace-stream :events deduped
                       :count (length deduped))))

;;; ─── Diff ───

(declaim (ftype (function (trace-stream trace-stream)
                          (values trace-diff-result &optional))
                trace-diff))
(defun trace-diff (left right)
  "Diff two trace streams. Pure."
  (declare (optimize (safety 3)))
  (let* ((l-events (ts-events left))
         (r-events (ts-events right))
         (l-table (make-hash-table :test 'eql))
         (r-table (make-hash-table :test 'eql))
         (matched 0)
         (mismatched 0)
         (missing-l 0)
         (missing-r 0)
         (details nil))
    ;; Index both sides by seq-id
    (dolist (ev l-events) (setf (gethash (tev-seq-id ev) l-table) ev))
    (dolist (ev r-events) (setf (gethash (tev-seq-id ev) r-table) ev))
    ;; Check left events
    (maphash (lambda (sid l-ev)
               (let ((r-ev (gethash sid r-table)))
                 (cond
                   ((null r-ev)
                    (incf missing-r)
                    (push (list :missing-right sid) details))
                   ((= (tev-payload-hash l-ev) (tev-payload-hash r-ev))
                    (incf matched))
                   (t
                    (incf mismatched)
                    (push (list :mismatch sid) details)))))
             l-table)
    ;; Check right-only
    (maphash (lambda (sid r-ev)
               (declare (ignore r-ev))
               (unless (gethash sid l-table)
                 (incf missing-l)
                 (push (list :missing-left sid) details)))
             r-table)
    (make-trace-diff-result
     :matched-count matched
     :mismatched-count mismatched
     :missing-left missing-l
     :missing-right missing-r
     :details (nreverse details))))

;;; ─── Parity Check ───

(declaim (ftype (function (trace-stream trace-stream)
                          (values boolean &optional))
                trace-parity-p))
(defun trace-parity-p (left right)
  "Check if two trace streams are equivalent. Pure."
  (declare (optimize (safety 3)))
  (let ((diff (trace-diff left right)))
    (and (zerop (tdr-mismatched-count diff))
         (zerop (tdr-missing-left diff))
         (zerop (tdr-missing-right diff)))))

;;; ─── JSON Serialization ───

(declaim (ftype (function (trace-event) (values string &optional))
                trace-event->json))
(defun trace-event->json (ev)
  "Serialize trace-event to deterministic JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"seq_id\":~D,\"timestamp\":~D,\"source\":\"~A\",\"kind\":\"~A\",\"payload_hash\":~D}"
          (tev-seq-id ev) (tev-timestamp ev)
          (tev-source-tag ev) (tev-event-kind ev)
          (tev-payload-hash ev)))

(declaim (ftype (function (trace-diff-result) (values string &optional))
                trace-diff->json))
(defun trace-diff->json (diff)
  "Serialize trace-diff-result to deterministic JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"matched\":~D,\"mismatched\":~D,\"missing_left\":~D,\"missing_right\":~D}"
          (tdr-matched-count diff) (tdr-mismatched-count diff)
          (tdr-missing-left diff) (tdr-missing-right diff)))
