;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-artifact-canonicalizer.lisp — typed S1-S6 path canonicalizer core
;;; Bead: agent-orrery-fwu

(in-package #:orrery/adapter)

(defstruct (canonical-web-artifact (:conc-name cwa-))
  (scenario-id "" :type string)
  (artifact-kind :machine-report :type evidence-artifact-kind)
  (original-path "" :type string)
  (canonical-path "" :type string)
  (present-p nil :type boolean))

(defstruct (playwright-canonicalization-report (:conc-name pcr-))
  (pass-p nil :type boolean)
  (records nil :type list)
  (missing-scenarios nil :type list)
  (detail "" :type string))

(declaim
 (ftype (function (string) (values string &optional)) normalize-path-slashes)
 (ftype (function (string evidence-artifact-kind string) (values string &optional))
        canonicalize-playwright-artifact-path)
 (ftype (function (string) (values list &optional)) collect-canonical-web-artifacts)
 (ftype (function (list) (values list &optional)) compute-missing-s1-s6)
 (ftype (function (string) (values playwright-canonicalization-report &optional))
        build-playwright-canonicalization-report)
 (ftype (function (playwright-canonicalization-report) (values string &optional))
        playwright-canonicalization-report->json))

(defun normalize-path-slashes (path)
  (declare (type string path))
  (substitute #\/ #\\ path))

(defun %artifact-kind-segment (kind)
  (declare (type evidence-artifact-kind kind))
  (case kind
    (:screenshot "screenshots")
    (:trace "traces")
    (:machine-report "reports")
    (otherwise "other")))

(defun canonicalize-playwright-artifact-path (scenario-id artifact-kind original-path)
  (declare (type string scenario-id original-path)
           (type evidence-artifact-kind artifact-kind))
  (let* ((leaf (file-namestring (pathname original-path)))
         (kind-segment (%artifact-kind-segment artifact-kind)))
    (format nil "~A/~A/~A"
            (string-upcase scenario-id)
            kind-segment
            (normalize-path-slashes leaf))))

(defun %pathname-file-p (p)
  (and (pathname-name p) (not (equal (pathname-name p) ""))))

(defun %path-present-p (p)
  (declare (type pathname p))
  (and (probe-file p)
       (or (ignore-errors
             (> (with-open-file (s p :direction :input :element-type '(unsigned-byte 8))
                  (file-length s))
                0))
           t)))

(defun collect-canonical-web-artifacts (artifacts-root)
  (declare (type string artifacts-root))
  (let ((out nil)
        (root (pathname artifacts-root)))
    (when (probe-file root)
      (dolist (p (directory (merge-pathnames (make-pathname :name :wild :type :wild :directory '(:relative :wild-inferiors))
                                             root)))
        (when (%pathname-file-p p)
          (let* ((full (namestring p))
                 (sid (or (infer-playwright-scenario-id full) ""))
                 (kind (infer-web-artifact-kind full)))
            (when (plusp (length sid))
              (push (make-canonical-web-artifact
                     :scenario-id sid
                     :artifact-kind kind
                     :original-path full
                     :canonical-path (canonicalize-playwright-artifact-path sid kind full)
                     :present-p (%path-present-p p))
                    out))))))
    (sort (nreverse out)
          #'string<
          :key #'cwa-canonical-path)))

(defun compute-missing-s1-s6 (records)
  (declare (type list records))
  (let ((missing nil))
    (dolist (sid *playwright-required-scenarios*)
      (let ((shot (find-if (lambda (r)
                             (and (string= sid (cwa-scenario-id r))
                                  (eq :screenshot (cwa-artifact-kind r))
                                  (cwa-present-p r)))
                           records))
            (trace (find-if (lambda (r)
                              (and (string= sid (cwa-scenario-id r))
                                   (eq :trace (cwa-artifact-kind r))
                                   (cwa-present-p r)))
                            records)))
        (unless (and shot trace)
          (push sid missing))))
    (nreverse missing)))

(defun build-playwright-canonicalization-report (artifacts-root)
  (declare (type string artifacts-root))
  (let* ((records (collect-canonical-web-artifacts artifacts-root))
         (missing (compute-missing-s1-s6 records))
         (pass-p (null missing)))
    (make-playwright-canonicalization-report
     :pass-p pass-p
     :records records
     :missing-scenarios missing
     :detail (format nil "records=~D missing=~D"
                     (length records)
                     (length missing)))))

(defun playwright-canonicalization-report->json (report)
  (declare (type playwright-canonicalization-report report))
  (format nil
          "{\"pass\":~A,\"records\":~D,\"missing\":~D,\"detail\":\"~A\"}"
          (if (pcr-pass-p report) "true" "false")
          (length (pcr-records report))
          (length (pcr-missing-scenarios report))
          (pcr-detail report)))
