;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test playwright-evidence-locker-suite)

(defun %mk-temp-locker-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-playwright-locker-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-locker-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-locker-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (playwright-evidence-locker-suite lock-pass)
  (let ((dir (%mk-temp-locker-dir "ok")))
    (unwind-protect
         (progn
           (%touch-locker-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-locker-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-locker-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let* ((lock (orrery/adapter:build-playwright-evidence-lock dir "cd e2e && ./run-e2e.sh"))
                  (json (orrery/adapter:playwright-evidence-lock->json lock)))
             (true (orrery/adapter:pel-pass-p lock))
             (is = 0 (length (orrery/adapter:pel-missing-scenarios lock)))
             (true (search "\"command_hash\":" json))
             (true (search "\"missing_scenarios\":[]" json))))
      (%cleanup-locker-dir dir))))

(define-test (playwright-evidence-locker-suite lock-fails-command-drift)
  (let ((dir (%mk-temp-locker-dir "cmd")))
    (unwind-protect
         (progn
           (%touch-locker-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-locker-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-locker-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (ignore-errors (delete-file (merge-pathnames "S6-trace.zip" dir)))
           (let* ((lock (orrery/adapter:build-playwright-evidence-lock dir "make e2e"))
                  (json (orrery/adapter:playwright-evidence-lock->json lock)))
             (false (orrery/adapter:pel-pass-p lock))
             (false (orrery/adapter:pel-command-match-p lock))
             (true (search "\"missing_scenarios\":[\"S6\"]" json))))
      (%cleanup-locker-dir dir))))
