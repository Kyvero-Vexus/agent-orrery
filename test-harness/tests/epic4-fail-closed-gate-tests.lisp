;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test epic4-fail-closed-gate-suite)

(defun %mk-temp-epic4-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-epic4-gate-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-epic4-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-epic4-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (epic4-fail-closed-gate-suite pass-with-complete-s1-s6)
  (let ((dir (%mk-temp-epic4-dir "ok")))
    (unwind-protect
         (progn
           (%touch-epic4-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-epic4-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-epic4-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let* ((r (orrery/adapter:evaluate-epic4-fail-closed-gate dir "cd e2e && ./run-e2e.sh"))
                  (json (orrery/adapter:epic4-fail-closed-result->json r)))
             (true (orrery/adapter:e4fcr-pass-p r))
             (is = 0 (length (orrery/adapter:e4fcr-missing-scenarios r)))
             (true (search "\"command_hash\":" json))
             (true (search "\"missing_scenarios\":[]" json))))
      (%cleanup-epic4-dir dir))))

(define-test (epic4-fail-closed-gate-suite fail-missing-scenario-trace)
  (let ((dir (%mk-temp-epic4-dir "fail")))
    (unwind-protect
         (progn
           (%touch-epic4-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-epic4-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png"))
           (let* ((r (orrery/adapter:evaluate-epic4-fail-closed-gate dir "cd e2e && ./run-e2e.sh"))
                  (json (orrery/adapter:epic4-fail-closed-result->json r)))
             (false (orrery/adapter:e4fcr-pass-p r))
             (true (find "S1" (orrery/adapter:e4fcr-missing-scenarios r) :test #'string=))
             (true (search "\"missing_scenarios\":[" json))))
      (%cleanup-epic4-dir dir))))

(define-test (epic4-fail-closed-gate-suite fail-command-drift)
  (let ((dir (%mk-temp-epic4-dir "cmd")))
    (unwind-protect
         (progn
           (%touch-epic4-file (merge-pathnames "playwright-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-epic4-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-epic4-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let ((r (orrery/adapter:evaluate-epic4-fail-closed-gate dir "make e2e")))
             (false (orrery/adapter:e4fcr-pass-p r))
             (false (orrery/adapter:e4fcr-command-match-p r))))
      (%cleanup-epic4-dir dir))))
