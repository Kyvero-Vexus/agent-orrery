;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test playwright-witness-exporter-suite)

(defun %mk-temp-web-witness-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-web-witness-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-web-witness-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-web-witness-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-web-witness-artifacts (dir)
  (%touch-web-witness-file (merge-pathnames "playwright-report.json" dir) "S1 S2 S3 S4 S5 S6")
  (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
    (%touch-web-witness-file (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) dir)
                             (format nil "png-~A" sid))
    (%touch-web-witness-file (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) dir)
                             (format nil "zip-~A" sid))))

(define-test (playwright-witness-exporter-suite pass-on-complete-evidence)
  (let ((dir (%mk-temp-web-witness-dir "ok")))
    (unwind-protect
         (progn
           (%seed-web-witness-artifacts dir)
           (let* ((bundle (orrery/adapter:evaluate-playwright-witness-bundle dir "cd e2e && ./run-e2e.sh"))
                  (json (orrery/adapter:playwright-witness-bundle->json bundle)))
             (true (orrery/adapter:pwb-pass-p bundle))
             (true (orrery/adapter:pwb-command-match-p bundle))
             (true (orrery/adapter:pwb-closure-pass-p bundle))
             (is = 6 (length (orrery/adapter:pwb-screenshot-digest-map bundle)))
             (is = 6 (length (orrery/adapter:pwb-trace-digest-map bundle)))
             (true (search "\"signature\"" json))))
      (%cleanup-web-witness-dir dir))))

(define-test (playwright-witness-exporter-suite fail-on-command-drift)
  (let ((dir (%mk-temp-web-witness-dir "drift")))
    (unwind-protect
         (progn
           (%seed-web-witness-artifacts dir)
           (let ((bundle (orrery/adapter:evaluate-playwright-witness-bundle dir "cd e2e && ./wrong.sh")))
             (false (orrery/adapter:pwb-pass-p bundle))
             (false (orrery/adapter:pwb-command-match-p bundle))))
      (%cleanup-web-witness-dir dir))))
