;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; fixture-corpus-gen.lisp — Deterministic fixture corpus generator
;;;
;;; Converts trace snapshots into stable fixture corpora for regression testing.

(in-package #:orrery/adapter)

;;; ─── Types ───

(defstruct (corpus-entry (:conc-name ce-))
  "Single fixture in the corpus."
  (endpoint-path "" :type string)
  (event-kind :session :type event-kind)
  (expected-hash  0 :type fixnum)
  (timestamp      0 :type fixnum)
  (payload       "" :type string))

(defstruct (corpus-manifest (:conc-name cman-))
  "Complete fixture corpus with metadata."
  (entries   nil :type list)
  (version     1 :type fixnum)
  (seed        0 :type fixnum)
  (checksum    0 :type fixnum)
  (entry-count 0 :type fixnum))

(defstruct (corpus-diff (:conc-name cdiff-))
  "Delta between two fixture corpora."
  (added     0 :type fixnum)
  (removed   0 :type fixnum)
  (changed   0 :type fixnum)
  (unchanged 0 :type fixnum)
  (details nil :type list))

;;; ─── Corpus Entry Construction ───

(declaim (ftype (function (string event-kind string fixnum)
                          (values corpus-entry &optional))
                make-corpus-entry-from-sample))
(defun make-corpus-entry-from-sample (path kind payload timestamp)
  "Create a corpus entry from endpoint sample data. Pure."
  (declare (optimize (safety 3)))
  (make-corpus-entry
   :endpoint-path path
   :event-kind kind
   :expected-hash (simple-payload-hash payload)
   :timestamp timestamp
   :payload payload))

;;; ─── Entry Ordering ───

(declaim (ftype (function (corpus-entry corpus-entry)
                          (values boolean &optional))
                corpus-entry<))
(defun corpus-entry< (a b)
  "Sort entries by (path, event-kind, timestamp). Pure."
  (declare (optimize (safety 3)))
  (let ((pa (ce-endpoint-path a))
        (pb (ce-endpoint-path b)))
    (cond
      ((string< pa pb) t)
      ((string> pa pb) nil)
      (t (let ((ka (symbol-name (ce-event-kind a)))
               (kb (symbol-name (ce-event-kind b))))
           (cond
             ((string< ka kb) t)
             ((string> ka kb) nil)
             (t (< (ce-timestamp a) (ce-timestamp b)))))))))

;;; ─── Corpus Checksum ───

(declaim (ftype (function (list) (values fixnum &optional))
                compute-corpus-checksum))
(defun compute-corpus-checksum (sorted-entries)
  "Deterministic checksum from sorted entry list. Pure."
  (declare (optimize (safety 3)))
  (logand
   (sxhash
    (mapcar (lambda (e)
              (list (ce-endpoint-path e) (ce-expected-hash e)))
            sorted-entries))
   most-positive-fixnum))

;;; ─── Build Corpus ───

(declaim (ftype (function (list &key (:version fixnum) (:seed fixnum))
                          (values corpus-manifest &optional))
                build-corpus))
(defun build-corpus (entries &key (version 1) (seed 0))
  "Build a corpus manifest from entries. Sorts, checksums. Pure."
  (declare (optimize (safety 3)))
  (let* ((sorted (sort (copy-list entries) #'corpus-entry<))
         (checksum (compute-corpus-checksum sorted)))
    (make-corpus-manifest
     :entries sorted
     :version version
     :seed seed
     :checksum checksum
     :entry-count (length sorted))))

;;; ─── Corpus Diff ───

(declaim (ftype (function (corpus-manifest corpus-manifest)
                          (values corpus-diff &optional))
                diff-corpora))
(defun diff-corpora (old new)
  "Diff two corpus manifests. Pure."
  (declare (optimize (safety 3)))
  (let ((old-table (make-hash-table :test 'equal))
        (new-table (make-hash-table :test 'equal))
        (added 0) (removed 0) (changed 0) (unchanged 0)
        (details nil))
    ;; Index by path
    (dolist (e (cman-entries old))
      (setf (gethash (ce-endpoint-path e) old-table) e))
    (dolist (e (cman-entries new))
      (setf (gethash (ce-endpoint-path e) new-table) e))
    ;; Check new entries against old
    (maphash (lambda (path new-e)
               (let ((old-e (gethash path old-table)))
                 (cond
                   ((null old-e)
                    (incf added)
                    (push (list :added path) details))
                   ((= (ce-expected-hash old-e) (ce-expected-hash new-e))
                    (incf unchanged))
                   (t
                    (incf changed)
                    (push (list :changed path) details)))))
             new-table)
    ;; Check for removed
    (maphash (lambda (path old-e)
               (declare (ignore old-e))
               (unless (gethash path new-table)
                 (incf removed)
                 (push (list :removed path) details)))
             old-table)
    (make-corpus-diff
     :added added :removed removed
     :changed changed :unchanged unchanged
     :details (sort (copy-list details) #'string<
                    :key (lambda (d) (second d))))))

;;; ─── Stability Check ───

(declaim (ftype (function (corpus-manifest corpus-manifest)
                          (values boolean &optional))
                corpus-stable-p))
(defun corpus-stable-p (old new)
  "Check if corpus is stable (no regressions). Pure."
  (declare (optimize (safety 3)))
  (let ((diff (diff-corpora old new)))
    (and (zerop (cdiff-removed diff))
         (zerop (cdiff-changed diff)))))

;;; ─── JSON Serialization ───

(declaim (ftype (function (corpus-entry) (values string &optional))
                entry->fixture-json))
(defun entry->fixture-json (entry)
  "Serialize corpus entry to fixture JSON record. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"path\":\"~A\",\"kind\":\"~A\",\"hash\":~D,\"timestamp\":~D,\"payload\":\"~A\"}"
          (ce-endpoint-path entry)
          (ce-event-kind entry)
          (ce-expected-hash entry)
          (ce-timestamp entry)
          ;; Escape payload quotes
          (with-output-to-string (s)
            (loop :for c :across (ce-payload entry)
                  :do (if (char= c #\") (write-string "\\\"" s) (write-char c s))))))

(declaim (ftype (function (corpus-manifest) (values string &optional))
                corpus->json))
(defun corpus->json (manifest)
  "Serialize corpus manifest to deterministic JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"version\":~D,\"seed\":~D,\"checksum\":~D,\"entry_count\":~D,\"entries\":[~{~A~^,~}]}"
          (cman-version manifest)
          (cman-seed manifest)
          (cman-checksum manifest)
          (cman-entry-count manifest)
          (mapcar #'entry->fixture-json (cman-entries manifest))))

(declaim (ftype (function (corpus-diff) (values string &optional))
                corpus-diff->json))
(defun corpus-diff->json (diff)
  "Serialize corpus diff to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"added\":~D,\"removed\":~D,\"changed\":~D,\"unchanged\":~D}"
          (cdiff-added diff) (cdiff-removed diff)
          (cdiff-changed diff) (cdiff-unchanged diff)))
