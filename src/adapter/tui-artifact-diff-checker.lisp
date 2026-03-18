;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-artifact-diff-checker.lisp — deterministic normalization + diff checks for TUI artifacts
;;; Bead: agent-orrery-s95

(in-package #:orrery/adapter)

(defstruct (tui-artifact-record (:conc-name tar-))
  (scenario-id "" :type string)
  (kind :screenshot :type keyword)
  (path "" :type string)
  (present-p nil :type boolean)
  (size-bytes 0 :type integer))

(defstruct (tui-diff-report (:conc-name tdr-))
  (pass-p nil :type boolean)
  (missing-in-current nil :type list)
  (extra-in-current nil :type list)
  (mismatch-count 0 :type fixnum)
  (detail "" :type string))

(declaim
 (ftype (function (string) (values (or null string) &optional)) infer-tui-scenario-id-from-path)
 (ftype (function (string) (values keyword &optional)) infer-tui-kind-from-path)
 (ftype (function (string) (values list &optional)) collect-normalized-tui-artifacts)
 (ftype (function (string string) (values tui-diff-report &optional)) compare-tui-artifact-bundles)
 (ftype (function (tui-diff-report) (values string &optional)) tui-diff-report->json))

(defun infer-tui-scenario-id-from-path (filename)
  (declare (type string filename))
  (let ((u (string-upcase filename)))
    (loop for sid in '("T1" "T2" "T3" "T4" "T5" "T6")
          when (search sid u)
            do (return sid)
          finally (return nil))))

(defun infer-tui-kind-from-path (filename)
  (declare (type string filename))
  (let ((l (string-downcase filename)))
    (cond
      ((or (search ".png" l) (search ".jpg" l) (search ".jpeg" l)) :screenshot)
      ((or (search ".txt" l) (search "transcript" l)) :transcript)
      ((search ".cast" l) :asciicast)
      ((or (search ".json" l) (search "report" l)) :machine-report)
      (t :unknown))))

(defun %file-size (path)
  (or (ignore-errors
        (with-open-file (s path :direction :input :element-type '(unsigned-byte 8))
          (file-length s)))
      0))

(defun collect-normalized-tui-artifacts (root)
  (declare (type string root))
  (let ((out nil))
    (when (probe-file root)
      (dolist (p (directory (merge-pathnames (make-pathname :name :wild :type :wild :directory '(:relative :wild-inferiors))
                                             (pathname root))))
        (let* ((base (file-namestring p))
               (sid (or (infer-tui-scenario-id-from-path base) "SUITE"))
               (kind (infer-tui-kind-from-path base))
               (size (%file-size p))
               (present (> size 0)))
          (unless (eq kind :unknown)
            (push (make-tui-artifact-record
                   :scenario-id sid
                   :kind kind
                   :path (string-downcase (namestring p))
                   :present-p present
                   :size-bytes size)
                  out)))))
    (sort (nreverse out)
          (lambda (a b)
            (or (string< (tar-scenario-id a) (tar-scenario-id b))
                (and (string= (tar-scenario-id a) (tar-scenario-id b))
                     (string< (symbol-name (tar-kind a)) (symbol-name (tar-kind b)))))))))

(defun %record-key (r)
  (format nil "~A|~A" (tar-scenario-id r) (tar-kind r)))

(defun compare-tui-artifact-bundles (expected-root current-root)
  (declare (type string expected-root current-root))
  (let* ((exp (collect-normalized-tui-artifacts expected-root))
         (cur (collect-normalized-tui-artifacts current-root))
         (exp-keys (mapcar #'%record-key exp))
         (cur-keys (mapcar #'%record-key cur))
         (missing (remove-if (lambda (k) (member k cur-keys :test #'string=)) exp-keys))
         (extra (remove-if (lambda (k) (member k exp-keys :test #'string=)) cur-keys))
         (mismatch (+ (length missing) (length extra))))
    (make-tui-diff-report
     :pass-p (zerop mismatch)
     :missing-in-current missing
     :extra-in-current extra
     :mismatch-count mismatch
     :detail (format nil "missing=~D extra=~D" (length missing) (length extra)))))

(defun tui-diff-report->json (r)
  (declare (type tui-diff-report r))
  (format nil
          "{\"pass\":~A,\"missing\":~D,\"extra\":~D,\"mismatch_count\":~D,\"detail\":\"~A\"}"
          (if (tdr-pass-p r) "true" "false")
          (length (tdr-missing-in-current r))
          (length (tdr-extra-in-current r))
          (tdr-mismatch-count r)
          (tdr-detail r)))
