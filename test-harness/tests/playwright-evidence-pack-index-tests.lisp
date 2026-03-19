;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test playwright-evidence-pack-index-suite)

(defun %mk-temp-pack-index-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-playwright-index-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-pack-index-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-pack-index-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (playwright-evidence-pack-index-suite index-pass)
  (let ((dir (%mk-temp-pack-index-dir "ok")))
    (unwind-protect
         (progn
           (%touch-pack-index-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-pack-index-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-pack-index-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let ((idx (orrery/adapter:build-playwright-evidence-pack-index dir "cd e2e && ./run-e2e.sh")))
             (true (orrery/adapter:pepi-pass-p idx))
             (is = 0 (length (orrery/adapter:pepi-missing-scenarios idx)))))
      (%cleanup-pack-index-dir dir))))

(define-test (playwright-evidence-pack-index-suite index-fails-command-drift)
  (let ((dir (%mk-temp-pack-index-dir "cmd")))
    (unwind-protect
         (progn
           (%touch-pack-index-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-pack-index-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-pack-index-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let ((idx (orrery/adapter:build-playwright-evidence-pack-index dir "make e2e")))
             (false (orrery/adapter:pepi-pass-p idx))
             (false (orrery/adapter:pepi-command-match-p idx))))
      (%cleanup-pack-index-dir dir))))
