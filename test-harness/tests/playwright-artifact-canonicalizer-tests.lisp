;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-artifact-canonicalizer-tests.lisp — tests for fwu canonicalizer

(in-package #:orrery/harness-tests)

(define-test playwright-artifact-canonicalizer-suite)

(defun %mk-temp-playwright-canon-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-playwright-canon-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-canon-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-temp-playwright-canon-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (playwright-artifact-canonicalizer-suite canonical-path-shape)
  (is string=
      "S2/screenshots/S2-home.png"
      (orrery/adapter:canonicalize-playwright-artifact-path "S2" :screenshot "/tmp/S2-home.png")))

(define-test (playwright-artifact-canonicalizer-suite complete-s1-s6-pass)
  (let ((dir (%mk-temp-playwright-canon-dir "ok")))
    (unwind-protect
         (progn
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-canon-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-canon-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let ((report (orrery/adapter:build-playwright-canonicalization-report dir)))
             (true (orrery/adapter:pcr-pass-p report))
             (is = 0 (length (orrery/adapter:pcr-missing-scenarios report)))))
      (%cleanup-temp-playwright-canon-dir dir))))

(define-test (playwright-artifact-canonicalizer-suite missing-s6-fails)
  (let ((dir (%mk-temp-playwright-canon-dir "fail")))
    (unwind-protect
         (progn
           (dolist (sid '("S1" "S2" "S3" "S4" "S5"))
             (%touch-canon-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-canon-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let ((report (orrery/adapter:build-playwright-canonicalization-report dir)))
             (false (orrery/adapter:pcr-pass-p report))
             (true (find "S6" (orrery/adapter:pcr-missing-scenarios report) :test #'string=))))
      (%cleanup-temp-playwright-canon-dir dir))))
