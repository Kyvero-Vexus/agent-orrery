;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; transcript-capture.lisp — Typed transcript capture + replay harness
;;;
;;; Captures real OpenClaw JSON API transcripts and replays them as
;;; deterministic fixtures for contract tests.

(in-package #:orrery/adapter)

;;; ─── Transcript Entry ───

(deftype transcript-direction ()
  '(member :request :response))

(defstruct (transcript-entry
             (:constructor make-transcript-entry
                 (&key direction method path status-code
                       content-type body timestamp))
             (:conc-name te-))
  "One captured request/response pair."
  (direction :request :type transcript-direction)
  (method :get :type keyword)
  (path "" :type string)
  (status-code 0 :type fixnum)
  (content-type "" :type string)
  (body "" :type string)
  (timestamp 0 :type integer))

;;; ─── Transcript ───

(defstruct (transcript
             (:constructor make-transcript
                 (&key name target-url entries captured-at notes))
             (:conc-name tx-))
  "A captured API transcript for replay."
  (name "" :type string)
  (target-url "" :type string)
  (entries '() :type list)
  (captured-at 0 :type integer)
  (notes "" :type string))

;;; ─── Replay Result ───

(defstruct (replay-result
             (:constructor make-replay-result
                 (&key transcript matches mismatches
                       replay-verdict))
             (:conc-name rr-))
  "Result of replaying a transcript against current adapter state."
  (transcript nil :type (or null transcript))
  (matches '() :type list)
  (mismatches '() :type list)
  (replay-verdict :skip :type contract-verdict))

;;; ─── Capture ───

(declaim (ftype (function (string keyword fixnum string string)
                          (values transcript-entry &optional))
                capture-response)
         (ftype (function (string list) (values transcript &optional))
                build-transcript)
         (ftype (function (transcript) (values string &optional))
                transcript-to-json)
         (ftype (function (string) (values (or null transcript) &optional))
                load-transcript-from-json)
         (ftype (function (transcript) (values replay-result &optional))
                replay-transcript))

(defun capture-response (path method status-code content-type body)
  "Capture a single API response as a transcript entry pair."
  (declare (type string path content-type body)
           (type keyword method) (type fixnum status-code))
  (let ((ts (get-universal-time)))
    (make-transcript-entry
     :direction :response
     :method method
     :path path
     :status-code status-code
     :content-type content-type
     :body body
     :timestamp ts)))

(defun build-transcript (name entries)
  "Build a transcript from a list of captured entries."
  (declare (type string name) (type list entries))
  (make-transcript
   :name name
   :target-url ""
   :entries entries
   :captured-at (get-universal-time)
   :notes ""))

;;; ─── Replay ───

(defun replay-transcript (transcript)
  "Replay a transcript and validate each entry produces expected results.
   For now, validates structural integrity of the transcript itself."
  (declare (type transcript transcript))
  (let ((matches '())
        (mismatches '()))
    (dolist (entry (tx-entries transcript))
      (cond
        ;; Valid response entries have non-zero status and non-empty path
        ((and (eq :response (te-direction entry))
              (plusp (te-status-code entry))
              (plusp (length (te-path entry))))
         (push entry matches))
        ;; Request entries are structural markers
        ((eq :request (te-direction entry))
         (push entry matches))
        ;; Malformed entries
        (t
         (push entry mismatches))))
    (make-replay-result
     :transcript transcript
     :matches (nreverse matches)
     :mismatches (nreverse mismatches)
     :replay-verdict (if (null mismatches) :pass :fail))))

;;; ─── JSON Serialization ───

(defun transcript-to-json (transcript)
  "Serialize transcript to deterministic JSON for storage/replay."
  (declare (type transcript transcript))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"name\":" s)
    (emit-json-string (tx-name transcript) s)
    (write-string ",\"target_url\":" s)
    (emit-json-string (tx-target-url transcript) s)
    (write-string ",\"captured_at\":" s)
    (format s "~D" (tx-captured-at transcript))
    (write-string ",\"entries\":[" s)
    (let ((first t))
      (dolist (e (tx-entries transcript))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"direction\":" s)
        (emit-json-string (string-downcase (symbol-name (te-direction e))) s)
        (write-string ",\"method\":" s)
        (emit-json-string (string-downcase (symbol-name (te-method e))) s)
        (write-string ",\"path\":" s)
        (emit-json-string (te-path e) s)
        (write-string ",\"status_code\":" s)
        (format s "~D" (te-status-code e))
        (write-string ",\"content_type\":" s)
        (emit-json-string (te-content-type e) s)
        (write-string ",\"body\":" s)
        (emit-json-string (te-body e) s)
        (write-string "}" s)))
    (write-string "]}" s)))

(defun load-transcript-from-json (json-string)
  "Load a transcript from JSON string. Returns nil on parse failure.
   Stub: production version would use jzon."
  (declare (type string json-string))
  (if (and (plusp (length json-string))
           (char= #\{ (char json-string 0)))
      (make-transcript
       :name "(loaded)" :target-url "" :entries '()
       :captured-at 0 :notes "Loaded from JSON")
      nil))
