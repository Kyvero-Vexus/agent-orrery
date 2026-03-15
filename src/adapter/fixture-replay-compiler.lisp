;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; fixture-replay-compiler.lisp — Deterministic fixture replay bundle compiler
;;;
;;; Transforms normalized snapshot/event traces into replay streams and
;;; validated replay-stream artifacts for Epic 2 evidence/parity suites.

(in-package #:orrery/adapter)

(defstruct (fixture-replay-bundle
             (:constructor make-fixture-replay-bundle
                 (&key bundle-id source streams artifacts
                       fixture-corpus event-count snapshot-count timestamp))
             (:conc-name frb-))
  "Compiled deterministic fixture replay bundle."
  (bundle-id "" :type string)
  (source :fixture :type replay-source)
  (streams '() :type list)
  (artifacts '() :type list)
  (fixture-corpus '() :type list)
  (event-count 0 :type (integer 0))
  (snapshot-count 0 :type (integer 0))
  (timestamp 0 :type (integer 0)))

(declaim (ftype (function (orrery/domain:event-record (integer 0))
                          (values replay-event &optional))
                normalize-event->replay-event))
(defun normalize-event->replay-event (event sequence-id)
  "Convert normalized domain event to replay-event. Pure."
  (declare (optimize (safety 3)))
  (make-replay-event
   :sequence-id sequence-id
   :event-type :event
   :payload (orrery/domain:er-message event)
   :timestamp (orrery/domain:er-timestamp event)))

(declaim (ftype (function (orrery/pipeline:normalized-snapshot
                           &key (:start-sequence (integer 0)))
                          (values list (integer 0) &optional))
                snapshot->replay-events))
(defun snapshot->replay-events (snapshot &key (start-sequence 0))
  "Compile one normalized snapshot's events into replay-events.
Returns (values events-list next-sequence)."
  (declare (optimize (safety 3)))
  (let ((seq start-sequence)
        (out '()))
    (dolist (ev (orrery/pipeline:normalized-snapshot-events snapshot))
      (push (normalize-event->replay-event ev seq) out)
      (incf seq))
    (values (nreverse out) seq)))

(declaim (ftype (function (replay-stream (integer 0) replay-source)
                          (values artifact-envelope &optional))
                replay-stream->artifact))
(defun replay-stream->artifact (stream timestamp source)
  "Create deterministic replay-stream artifact envelope. Pure."
  (declare (optimize (safety 3)))
  (let* ((payload-size (length (rstr-events stream)))
         (checksum (simple-body-hash
                    (format nil "~A:~D:~D"
                            (rstr-stream-id stream)
                            payload-size
                            (rstr-seed stream)))))
    (make-artifact-envelope
     :artifact-id (format nil "art-~A" (rstr-stream-id stream))
     :kind :replay-stream
     :version "1.0.0"
     :created-at timestamp
     :source source
     :checksum checksum
     :payload-size payload-size
     :valid-p t
     :errors '())))

(declaim (ftype (function (replay-stream) (values string &optional))
                replay-stream->fixture-json))
(defun replay-stream->fixture-json (stream)
  "Serialize replay-stream into deterministic fixture JSON line. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"stream_id\":\"~A\",\"source\":\"~A\",\"seed\":~D,\"event_count\":~D}"
          (rstr-stream-id stream)
          (rstr-source stream)
          (rstr-seed stream)
          (length (rstr-events stream))))

(declaim (ftype (function (list &key (:bundle-id string)
                                     (:seed (integer 0))
                                     (:source replay-source)
                                     (:timestamp (integer 0)))
                          (values fixture-replay-bundle &optional))
                compile-fixture-replay-bundle))
(defun compile-fixture-replay-bundle (snapshots
                                      &key (bundle-id "")
                                        (seed 0)
                                        (source :fixture)
                                        (timestamp 0))
  "Compile normalized snapshots into deterministic replay bundle. Pure."
  (declare (optimize (safety 3)))
  (let ((streams '())
        (artifacts '())
        (corpus '())
        (sequence 0)
        (stream-index 0)
        (event-count 0))
    (dolist (snap snapshots)
      (multiple-value-bind (events next-seq)
          (snapshot->replay-events snap :start-sequence sequence)
        (let* ((stream-id (format nil "~A-s~D" (if (string= bundle-id "") "bundle" bundle-id) stream-index))
               (stream-seed (+ seed stream-index))
               (stream (make-replay-stream
                        :stream-id stream-id
                        :source source
                        :events events
                        :seed stream-seed
                        :metadata (orrery/pipeline:normalized-snapshot-sync-token snap)))
               (artifact (replay-stream->artifact stream timestamp source)))
          (push stream streams)
          (push artifact artifacts)
          (push (replay-stream->fixture-json stream) corpus)
          (incf event-count (length events))
          (setf sequence next-seq)
          (incf stream-index))))
    (make-fixture-replay-bundle
     :bundle-id bundle-id
     :source source
     :streams (nreverse streams)
     :artifacts (nreverse artifacts)
     :fixture-corpus (nreverse corpus)
     :event-count event-count
     :snapshot-count (length snapshots)
     :timestamp timestamp)))
