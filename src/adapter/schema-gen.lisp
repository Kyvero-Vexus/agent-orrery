;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; schema-gen.lisp — Property-based generators for schema regression corpus
;;;
;;; Deterministic PRNG-driven generators for replay events, schema
;;; signatures, and regression corpora.

(in-package #:orrery/adapter)

;;; ─── Generator State ───

(defstruct (gen-state
             (:constructor make-gen-state (&key (seed 42) (counter 0)))
             (:conc-name gs-))
  "Deterministic generator state. Counter advances on each draw."
  (seed 42 :type (integer 0))
  (counter 0 :type (integer 0)))

;;; ─── Core PRNG ───

(declaim (ftype (function (gen-state) (values (integer 0) gen-state &optional))
                gen-next-raw))
(defun gen-next-raw (state)
  "Advance state, return raw pseudo-random non-negative integer.
   Uses simple LCG: next = (a*counter + c) mod m with seed mixing."
  (declare (optimize (safety 3)))
  (let* ((counter (1+ (gs-counter state)))
         ;; LCG parameters (Numerical Recipes)
         (raw (mod (+ (* 1664525 (+ (gs-seed state) counter)) 1013904223)
                   (expt 2 31)))
         (new-state (make-gen-state :seed (gs-seed state) :counter counter)))
    (values raw new-state)))

(declaim (ftype (function (gen-state (integer 0) (integer 0))
                          (values (integer 0) gen-state &optional))
                gen-integer))
(defun gen-integer (state min max)
  "Generate integer in [min, max]."
  (declare (optimize (safety 3)))
  (multiple-value-bind (raw new-state) (gen-next-raw state)
    (values (+ min (mod raw (1+ (- max min)))) new-state)))

(declaim (ftype (function (gen-state list) (values t gen-state &optional))
                gen-element))
(defun gen-element (state choices)
  "Pick one element from choices."
  (declare (optimize (safety 3)))
  (multiple-value-bind (idx new-state) (gen-integer state 0 (1- (length choices)))
    (values (nth idx choices) new-state)))

(declaim (ftype (function (gen-state (integer 1)) (values string gen-state &optional))
                gen-string))
(defun gen-string (state length)
  "Generate alphanumeric string of given length."
  (declare (optimize (safety 3)))
  (let ((chars "abcdefghijklmnopqrstuvwxyz0123456789")
        (result (make-string length))
        (s state))
    (dotimes (i length)
      (multiple-value-bind (idx ns) (gen-integer s 0 35)
        (setf (aref result i) (aref chars idx)
              s ns)))
    (values result s)))

;;; ─── Domain Generators ───

(declaim (ftype (function (gen-state (integer 0))
                          (values replay-event gen-state &optional))
                gen-replay-event))
(defun gen-replay-event (state seq-id)
  "Generate a replay event with given sequence-id."
  (declare (optimize (safety 3)))
  (multiple-value-bind (etype s1)
      (gen-element state '(:session :cron :health :usage :event :alert :probe))
    (multiple-value-bind (payload s2) (gen-string s1 8)
      (multiple-value-bind (ts s3) (gen-integer s2 1000000 9999999)
        (values (make-replay-event
                 :sequence-id seq-id
                 :event-type etype
                 :payload payload
                 :timestamp ts)
                s3)))))

(declaim (ftype (function (gen-state (integer 1 20))
                          (values replay-stream gen-state &optional))
                gen-replay-stream))
(defun gen-replay-stream (state event-count)
  "Generate a replay stream with event-count events."
  (declare (optimize (safety 3)))
  (multiple-value-bind (stream-id s1) (gen-string state 6)
    (let ((events '())
          (s s1))
      (dotimes (i event-count)
        (multiple-value-bind (ev ns) (gen-replay-event s (1+ i))
          (push ev events)
          (setf s ns)))
      (values (make-replay-stream
               :stream-id stream-id
               :source :synthetic
               :events (nreverse events)
               :seed (gs-seed state))
              s))))

(declaim (ftype (function (gen-state) (values string gen-state &optional))
                gen-snapshot-token))
(defun gen-snapshot-token (state)
  "Generate a sync-token style snapshot identifier."
  (declare (optimize (safety 3)))
  (multiple-value-bind (tok s1) (gen-string state 12)
    (values (concatenate 'string "snap-" tok) s1)))

(declaim (ftype (function (gen-state (integer 1 10))
                          (values list gen-state &optional))
                gen-snapshot-sequence))
(defun gen-snapshot-sequence (state count)
  "Generate a list of snapshot tokens."
  (declare (optimize (safety 3)))
  (let ((tokens '())
        (s state))
    (dotimes (i count)
      (multiple-value-bind (tok ns) (gen-snapshot-token s)
        (push tok tokens)
        (setf s ns)))
    (values (nreverse tokens) s)))

;;; ─── Schema Generators ───

(declaim (ftype (function (gen-state) (values field-sig gen-state &optional))
                gen-field-sig))
(defun gen-field-sig (state)
  "Generate a random field signature."
  (declare (optimize (safety 3)))
  (multiple-value-bind (name s1) (gen-string state 5)
    (multiple-value-bind (ftype s2)
        (gen-element s1 '(:string :integer :boolean :list :object :null))
      (multiple-value-bind (req-n s3) (gen-integer s2 0 1)
        (values (make-field-sig
                 :name name
                 :field-type ftype
                 :required-p (= req-n 1)
                 :path name)
                s3)))))

(declaim (ftype (function (gen-state string (integer 1 10))
                          (values schema-sig gen-state &optional))
                gen-schema-sig))
(defun gen-schema-sig (state endpoint field-count)
  "Generate a schema signature with field-count fields."
  (declare (optimize (safety 3)))
  (let ((fields '())
        (s state))
    (dotimes (i field-count)
      (multiple-value-bind (f ns) (gen-field-sig s)
        (push f fields)
        (setf s ns)))
    (values (make-schema-sig
             :endpoint endpoint
             :version "1.0"
             :fields (nreverse fields))
            s)))

(declaim (ftype (function (gen-state string (integer 1 10))
                          (values schema-sig schema-sig gen-state &optional))
                gen-schema-pair))
(defun gen-schema-pair (state endpoint field-count)
  "Generate fixture/live schema pair. Live may drift from fixture."
  (declare (optimize (safety 3)))
  (multiple-value-bind (fixture s1) (gen-schema-sig state endpoint field-count)
    ;; Live starts as copy, maybe drift one field
    (multiple-value-bind (drift-n s2) (gen-integer s1 0 2)
      (let ((live-fields (copy-list (ss-fields fixture))))
        (when (and (> drift-n 0) live-fields)
          ;; Remove last field to simulate drift
          (setf live-fields (butlast live-fields)))
        (values fixture
                (make-schema-sig
                 :endpoint endpoint
                 :version "1.0"
                 :fields live-fields)
                s2)))))

;;; ─── Regression Corpus ───

(defstruct (regression-corpus
             (:constructor make-regression-corpus
                 (&key corpus-id seed streams snapshots
                       fixture-sigs live-sigs metadata))
             (:conc-name rc-))
  "Complete regression corpus for schema/decision validation."
  (corpus-id "" :type string)
  (seed 0 :type (integer 0))
  (streams '() :type list)
  (snapshots '() :type list)
  (fixture-sigs '() :type list)
  (live-sigs '() :type list)
  (metadata "" :type string))

(declaim (ftype (function ((integer 0) &key (:stream-count (integer 1 10))
                                            (:events-per-stream (integer 1 20))
                                            (:endpoint-count (integer 1 5))
                                            (:fields-per-schema (integer 1 10)))
                          regression-corpus)
                gen-regression-corpus))
(defun gen-regression-corpus (seed &key
                                     (stream-count 3)
                                     (events-per-stream 5)
                                     (endpoint-count 2)
                                     (fields-per-schema 4))
  "Generate a complete regression corpus from seed. Deterministic."
  (declare (optimize (safety 3)))
  (let ((s (make-gen-state :seed seed))
        (streams '())
        (fixture-sigs '())
        (live-sigs '()))
    ;; Generate streams
    (dotimes (i stream-count)
      (multiple-value-bind (stream ns) (gen-replay-stream s events-per-stream)
        (push stream streams)
        (setf s ns)))
    ;; Generate schema pairs
    (dotimes (i endpoint-count)
      (let ((ep (format nil "endpoint-~D" i)))
        (multiple-value-bind (fix live ns) (gen-schema-pair s ep fields-per-schema)
          (push fix fixture-sigs)
          (push live live-sigs)
          (setf s ns))))
    ;; Generate snapshots
    (multiple-value-bind (snaps ns) (gen-snapshot-sequence s 3)
      (declare (ignore ns))
      (make-regression-corpus
       :corpus-id (format nil "corpus-~D" seed)
       :seed seed
       :streams (nreverse streams)
       :snapshots snaps
       :fixture-sigs (nreverse fixture-sigs)
       :live-sigs (nreverse live-sigs)
       :metadata (format nil "Generated with seed ~D, ~D streams, ~D endpoints"
                         seed stream-count endpoint-count)))))
