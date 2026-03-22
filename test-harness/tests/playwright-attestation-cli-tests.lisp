;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test playwright-attestation-cli-suite)

(defun %mk-temp-playwright-attestation-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-playwright-attestation-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-playwright-attestation-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-playwright-attestation-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-playwright-attestation-artifacts (dir)
  (%touch-playwright-attestation-file (merge-pathnames "playwright-report.json" dir) "S1 S2 S3 S4 S5 S6")
  (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
    (%touch-playwright-attestation-file
     (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) dir)
     (format nil "png-~A" sid))
    (%touch-playwright-attestation-file
     (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) dir)
     (format nil "zip-~A" sid))))

(define-test (playwright-attestation-cli-suite pass-on-complete-s1-s6)
  (let ((dir (%mk-temp-playwright-attestation-dir "ok")))
    (unwind-protect
         (progn
           (%seed-playwright-attestation-artifacts dir)
           (let* ((report (orrery/adapter:evaluate-playwright-attestation-cli-report dir "cd e2e && ./run-e2e.sh"))
                  (json (orrery/adapter:playwright-attestation-cli-report->json report)))
             (true (orrery/adapter:pacr-pass-p report))
             (true (orrery/adapter:pacr-command-match-p report))
             (is = 6 (orrery/adapter:pacr-scenario-count report))
             (is = 0 (length (orrery/adapter:pacr-missing-scenarios report)))
             (true (search "\"attestations\":[{" json))
             (true (search "\"scenario_id\":\"S1\"" json))
             (true (search "\"transcript_digests\":" json))))
      (%cleanup-playwright-attestation-dir dir))))

(define-test (playwright-attestation-cli-suite fails-on-command-drift)
  (let ((dir (%mk-temp-playwright-attestation-dir "drift")))
    (unwind-protect
         (progn
           (%seed-playwright-attestation-artifacts dir)
           (let ((report (orrery/adapter:evaluate-playwright-attestation-cli-report dir "cd e2e && ./wrong.sh")))
             (false (orrery/adapter:pacr-pass-p report))
             (false (orrery/adapter:pacr-command-match-p report))))
      (%cleanup-playwright-attestation-dir dir))))
