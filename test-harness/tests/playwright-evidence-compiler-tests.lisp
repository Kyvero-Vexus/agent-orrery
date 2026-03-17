;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-compiler-tests.lisp — Tests for Playwright S1-S6 compiler
;;; Bead: agent-orrery-yzx

(in-package #:orrery/harness-tests)

(define-test playwright-evidence-compiler-suite)

(defun %mk-temp-playwright-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-playwright-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-temp-playwright-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (playwright-evidence-compiler-suite infer-scenario-id)
  (is string= "S1" (orrery/adapter:infer-playwright-scenario-id "S1-homepage.png"))
  (is eq nil (orrery/adapter:infer-playwright-scenario-id "nonscenario.txt")))

(define-test (playwright-evidence-compiler-suite compile-complete-s1-s6)
  (let ((dir (%mk-temp-playwright-dir "ok")))
    (unwind-protect
         (progn
           (%touch-file (merge-pathnames "e2e-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let* ((m (orrery/adapter:compile-playwright-evidence-manifest
                      dir
                      "cd e2e && ./run-e2e.sh"))
                  (report (orrery/adapter:verify-runner-evidence
                           m
                           orrery/adapter:*default-web-scenarios*
                           orrery/adapter:*web-required-artifacts*
                           '(:machine-report)
                           orrery/adapter:*expected-web-command*)))
             (is eq :playwright-web (orrery/adapter:rem-runner-kind m))
             (is = 6 (length (orrery/adapter:rem-scenarios m)))
             (true (orrery/adapter:ecr-pass-p report))))
      (%cleanup-temp-playwright-dir dir))))

(define-test (playwright-evidence-compiler-suite compile-missing-s6-fails)
  (let ((dir (%mk-temp-playwright-dir "fail")))
    (unwind-protect
         (progn
           (%touch-file (merge-pathnames "e2e-report.json" dir) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5"))
             (%touch-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip"))
           (let* ((m (orrery/adapter:compile-playwright-evidence-manifest
                      dir
                      "cd e2e && ./run-e2e.sh"))
                  (report (orrery/adapter:verify-runner-evidence
                           m
                           orrery/adapter:*default-web-scenarios*
                           orrery/adapter:*web-required-artifacts*
                           '(:machine-report)
                           orrery/adapter:*expected-web-command*)))
             (false (orrery/adapter:ecr-pass-p report))))
      (%cleanup-temp-playwright-dir dir))))
