;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; schema-regression-generators.lisp — Property-based generators for regression corpora
;;;
;;; Seed-deterministic, pure generators that synthesize event/snapshot/schema
;;; permutations for schema and decision-core validation.

(in-package #:orrery/adapter)

;;; ─── PRNG State ───

(defstruct (gen-state
             (:constructor make-gen-state (&key (seed 0) (counter 0)))
             (:conc-name gs-))
  "Seed-controlled PRNG state. Threaded functionally — never mutated."
  (seed 0 :type (unsigned-byte 64))
  (counter 0 :type (integer 0)))

;;; ─── Xorshift64 PRNG ───

(declaim (ftype (function (gen-state) (values (unsigned-byte 64) gen-state &optional))
                gen-next-raw))
(defun gen-next-raw (state)
  "Advance the PRNG. Returns (VALUES raw-value new-state)."
  (declare (optimize (safety 3)))
  (let* ((x (gs-seed state))
         (x (logand (logxor x (ash x 13)) #xFFFFFFFFFFFFFFFF))
         (x (logand (logxor x (ash x -7)) #xFFFFFFFFFFFFFFFF))
         (x (logand (logxor x (ash x 17)) #xFFFFFFFFFFFFFFFF)))
    (values x (make-gen-state :seed x :counter (1+ (gs-counter state))))))

;;; ─── Typed Generators ───

(declaim (ftype (function (gen-state (integer 0) (integer 0))
                          (values (integer 0) gen-state &optional))
                gen-integer))
(defun gen-integer (state min max)
  "Generate an integer in [MIN, MAX]. Pure."
  (declare (optimize (safety 3)))
  (if (= min max)
      (values min state)
      (multiple-value-bind (raw new-state) (gen-next-raw state)
        (let ((range (1+ (- max min))))
          (values (+ min (mod raw range)) new-state)))))

(declaim (ftype (function (gen-state simple-vector)
                          (values t gen-state &optional))
                gen-element))
(defun gen-element (state vec)
  "Pick a random element from VEC. Pure."
  (declare (optimize (safety 3)))
  (multiple-value-bind (idx new-state)
      (gen-integer state 0 (1- (length vec)))
    (values (aref vec idx) new-state)))

(defvar *gen-chars* "abcdefghijklmnopqrstuvwxyz0123456789"
  "Character pool for generated strings.")

(declaim (ftype (function (gen-state (integer 0) (integer 0))
                          (values string gen-state &optional))
                gen-string))
(defun gen-string (state min-len max-len)
  "Generate a random alphanumeric string of length [MIN-LEN, MAX-LEN]. Pure."
  (declare (optimize (safety 3)))
  (multiple-value-bind (len st1) (gen-integer state min-len max-len)
    (let ((buf (make-array len :element-type 'character :fill-pointer 0))
          (pool *gen-chars*)
          (current-state st1))
      (dotimes (i len)
        (multiple-value-bind (idx new-st)
            (gen-integer current-state 0 (1- (length pool)))
          (vector-push (char pool idx) buf)
          (setf current-state new-st)))
      (values (coerce buf 'string) current-state))))

;;; ─── Event Generators ───

(defvar *gen-event-types* #(:session :cron :health :usage :event :alert :probe))

(declaim (ftype (function (gen-state (integer 0))
                          (values replay-event gen-state &optional))
                gen-replay-event))
(defun gen-replay-event (state seq-id)
  "Generate one replay-event with the given sequence-id. Pure."
  (declare (optimize (safety 3)))
  (multiple-value-bind (etype st1)
      (gen-element state *gen-event-types*)
    (multiple-value-bind (payload st2) (gen-string st1 0 40)
      (multiple-value-bind (ts st3) (gen-integer st2 1000 999999)
        (values (make-replay-event
                 :sequence-id seq-id
                 :event-type etype
                 :payload payload
                 :timestamp ts)
                st3)))))

(defvar *gen-sources* #(:fixture :live :synthetic))

(declaim (ftype (function (gen-state string (integer 1))
                          (values replay-stream gen-state &optional))
                gen-replay-stream))
(defun gen-replay-stream (state stream-id event-count)
  "Generate a replay-stream with EVENT-COUNT events (monotonically ordered). Pure."
  (declare (optimize (safety 3)))
  (let ((events '())
        (current-state state))
    (dotimes (i event-count)
      (multiple-value-bind (evt st) (gen-replay-event current-state (1+ i))
        (push evt events)
        (setf current-state st)))
    (multiple-value-bind (source st1) (gen-element current-state *gen-sources*)
      (values (make-replay-stream
               :stream-id stream-id
               :source source
               :events (nreverse events)
               :seed (gs-seed state)
               :metadata "")
              st1))))

;;; ─── Snapshot Generators ───

(declaim (ftype (function (gen-state) (values string gen-state &optional))
                gen-snapshot-token))
(defun gen-snapshot-token (state)
  "Generate a monotonically-friendly sync token (lexicographic ordering). Pure."
  (declare (optimize (safety 3)))
  ;; Tokens are "tok-NNNNN" where N is a zero-padded counter
  (let ((counter (gs-counter state)))
    (multiple-value-bind (_ new-state) (gen-next-raw state)
      (declare (ignore _))
      (values (format nil "tok-~5,'0D" counter) new-state))))

(declaim (ftype (function (gen-state (integer 1))
                          (values list gen-state &optional))
                gen-snapshot-sequence))
(defun gen-snapshot-sequence (state count)
  "Generate COUNT (cons token label) pairs with monotonically increasing tokens. Pure."
  (declare (optimize (safety 3)))
  (let ((snapshots '())
        (current-state state))
    (dotimes (i count)
      (multiple-value-bind (token st) (gen-snapshot-token current-state)
        (push (cons token (format nil "snap-~D" i)) snapshots)
        (setf current-state st)))
    (values (nreverse snapshots) current-state)))

;;; ─── Schema Generators ───

(defvar *gen-field-types* #(:string :integer :boolean :list :object :null))
(defvar *gen-field-names* #("id" "name" "status" "timestamp" "model"
                            "channel" "count" "error" "version" "data"))

(declaim (ftype (function (gen-state string)
                          (values field-sig gen-state &optional))
                gen-field-sig))
(defun gen-field-sig (state path)
  "Generate a random field signature. Pure."
  (declare (optimize (safety 3)))
  (multiple-value-bind (name st1) (gen-element state *gen-field-names*)
    (multiple-value-bind (ftype st2) (gen-element st1 *gen-field-types*)
      (multiple-value-bind (req-val st3) (gen-integer st2 0 1)
        (values (make-field-sig
                 :name name
                 :field-type ftype
                 :required-p (= req-val 1)
                 :path (format nil "~A.~A" path name))
                st3)))))

(declaim (ftype (function (gen-state string (integer 1))
                          (values schema-sig gen-state &optional))
                gen-schema-sig))
(defun gen-schema-sig (state endpoint field-count)
  "Generate a schema signature with FIELD-COUNT fields. Pure."
  (declare (optimize (safety 3)))
  (let ((fields '())
        (current-state state))
    (dotimes (i field-count)
      (multiple-value-bind (field st) (gen-field-sig current-state endpoint)
        (push field fields)
        (setf current-state st)))
    (multiple-value-bind (ts st1) (gen-integer current-state 1000 999999)
      (values (make-schema-sig
               :endpoint endpoint
               :version "1.0.0"
               :fields (nreverse fields)
               :timestamp ts)
              st1))))

(declaim (ftype (function (gen-state string (integer 1) (integer 0 100))
                          (values schema-sig schema-sig gen-state &optional))
                gen-schema-pair))
(defun gen-schema-pair (state endpoint field-count mutation-rate)
  "Generate a fixture/live schema pair. MUTATION-RATE (0-100) controls divergence.
   Pure."
  (declare (optimize (safety 3)))
  (multiple-value-bind (fixture st1) (gen-schema-sig state endpoint field-count)
    ;; Copy fixture, then mutate some fields
    (let ((live-fields '())
          (current-state st1))
      (dolist (ff (ss-fields fixture))
        (multiple-value-bind (roll st) (gen-integer current-state 0 99)
          (if (< roll mutation-rate)
              ;; Mutate: change type
              (multiple-value-bind (new-type st2) (gen-element st *gen-field-types*)
                (push (make-field-sig
                       :name (fs-name ff)
                       :field-type new-type
                       :required-p (fs-required-p ff)
                       :path (fs-path ff))
                      live-fields)
                (setf current-state st2))
              ;; Keep same
              (progn
                (push ff live-fields)
                (setf current-state st)))))
      (multiple-value-bind (ts st-final) (gen-integer current-state 1000 999999)
        (values fixture
                (make-schema-sig
                 :endpoint endpoint
                 :version "1.0.1"
                 :fields (nreverse live-fields)
                 :timestamp ts)
                st-final)))))

;;; ─── Regression Corpus ───

(defstruct (regression-corpus
             (:constructor make-regression-corpus
                 (&key corpus-id seed streams snapshots
                       fixture-sigs live-sigs metadata))
             (:conc-name rc-))
  "Complete regression corpus for schema/decision-core validation."
  (corpus-id "" :type string)
  (seed 0 :type (integer 0))
  (streams '() :type list)
  (snapshots '() :type list)
  (fixture-sigs '() :type list)
  (live-sigs '() :type list)
  (metadata "" :type string))

(declaim (ftype (function (gen-state
                           &key (:stream-count (integer 1))
                                (:event-count (integer 1))
                                (:snapshot-count (integer 1))
                                (:endpoint-count (integer 1))
                                (:field-count (integer 1))
                                (:mutation-rate (integer 0 100)))
                          (values regression-corpus gen-state &optional))
                gen-regression-corpus))
(defun gen-regression-corpus (state
                              &key (stream-count 5)
                                   (event-count 10)
                                   (snapshot-count 8)
                                   (endpoint-count 3)
                                   (field-count 5)
                                   (mutation-rate 20))
  "Generate a complete regression corpus. Seed-deterministic, pure."
  (declare (optimize (safety 3)))
  (let ((streams '())
        (fixture-sigs '())
        (live-sigs '())
        (original-seed (gs-seed state))
        (current-state state))
    ;; Generate replay streams
    (dotimes (i stream-count)
      (multiple-value-bind (stream st)
          (gen-replay-stream current-state
                             (format nil "rstream-~3,'0D" i)
                             event-count)
        (push stream streams)
        (setf current-state st)))
    ;; Generate snapshot sequence
    (multiple-value-bind (snaps st1)
        (gen-snapshot-sequence current-state snapshot-count)
      ;; Generate schema pairs
      (let ((st2 st1))
        (dotimes (i endpoint-count)
          (multiple-value-bind (fix live st)
              (gen-schema-pair st2
                               (format nil "/endpoint-~D" i)
                               field-count
                               mutation-rate)
            (push fix fixture-sigs)
            (push live live-sigs)
            (setf st2 st)))
        (values (make-regression-corpus
                 :corpus-id (format nil "corpus-~D" original-seed)
                 :seed original-seed
                 :streams (nreverse streams)
                 :snapshots snaps
                 :fixture-sigs (nreverse fixture-sigs)
                 :live-sigs (nreverse live-sigs)
                 :metadata (format nil "Generated with seed ~D: ~D streams, ~
                                        ~D snapshots, ~D endpoints"
                                   original-seed stream-count
                                   snapshot-count endpoint-count))
                st2)))))
