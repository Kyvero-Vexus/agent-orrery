;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test playwright-lockstep-checker-suite)

(defun %mk-temp-lockstep-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-lockstep-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-lockstep-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-lockstep-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (playwright-lockstep-checker-suite lockstep-pass)
  (let ((dir (%mk-temp-lockstep-dir "ok")))
    (unwind-protect
         (progn
           (%touch-lockstep-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-lockstep-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-lockstep-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let ((r (orrery/adapter:evaluate-playwright-lockstep dir "cd e2e && ./run-e2e.sh")))
             (true (orrery/adapter:plr-pass-p r))
             (is = 0 (length (orrery/adapter:plr-missing-scenarios r)))))
      (%cleanup-lockstep-dir dir))))

(define-test (playwright-lockstep-checker-suite lockstep-fails-command-drift)
  (let ((dir (%mk-temp-lockstep-dir "cmd")))
    (unwind-protect
         (progn
           (%touch-lockstep-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-lockstep-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-lockstep-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let ((r (orrery/adapter:evaluate-playwright-lockstep dir "make e2e")))
             (false (orrery/adapter:plr-pass-p r))
             (false (orrery/adapter:plr-command-match-p r))))
      (%cleanup-lockstep-dir dir))))
