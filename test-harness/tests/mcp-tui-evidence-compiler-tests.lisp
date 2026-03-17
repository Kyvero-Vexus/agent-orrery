;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-evidence-compiler-tests.lisp — Tests for mcp-tui T1-T6 compiler
;;; Bead: agent-orrery-y8p

(in-package #:orrery/harness-tests)

(define-test mcp-tui-evidence-compiler-suite)

(defun %mk-temp-tui-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-mcp-tui-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-tui-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-temp-tui-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (mcp-tui-evidence-compiler-suite infer-scenario-id)
  (is string= "T1" (orrery/adapter:infer-mcp-tui-scenario-id "T1-screen.png"))
  (is eq nil (orrery/adapter:infer-mcp-tui-scenario-id "no-scenario.cast")))

(define-test (mcp-tui-evidence-compiler-suite compile-complete-t1-t6)
  (let ((dir (%mk-temp-tui-dir "ok")))
    (unwind-protect
         (progn
           (%touch-tui-file (merge-pathnames "tui-e2e-report.json" dir) "report")
           (%touch-tui-file (merge-pathnames "tui-e2e-session.cast" dir) "cast")
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-tui-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-tui-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt"))
           (let* ((m (orrery/adapter:compile-mcp-tui-evidence-manifest
                      dir
                      "make e2e-tui"))
                  (report (orrery/adapter:verify-runner-evidence
                           m
                           orrery/adapter:*default-tui-scenarios*
                           orrery/adapter:*tui-required-artifacts*
                           '(:machine-report :asciicast)
                           orrery/adapter:*expected-tui-command*)))
             (is eq :mcp-tui-driver (orrery/adapter:rem-runner-kind m))
             (is = 6 (length (orrery/adapter:rem-scenarios m)))
             (true (orrery/adapter:ecr-pass-p report))))
      (%cleanup-temp-tui-dir dir))))

(define-test (mcp-tui-evidence-compiler-suite compile-missing-t6-fails)
  (let ((dir (%mk-temp-tui-dir "fail")))
    (unwind-protect
         (progn
           (%touch-tui-file (merge-pathnames "tui-e2e-report.json" dir) "report")
           (%touch-tui-file (merge-pathnames "tui-e2e-session.cast" dir) "cast")
           (dolist (sid '("T1" "T2" "T3" "T4" "T5"))
             (%touch-tui-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-tui-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt"))
           (let* ((m (orrery/adapter:compile-mcp-tui-evidence-manifest
                      dir
                      "make e2e-tui"))
                  (report (orrery/adapter:verify-runner-evidence
                           m
                           orrery/adapter:*default-tui-scenarios*
                           orrery/adapter:*tui-required-artifacts*
                           '(:machine-report :asciicast)
                           orrery/adapter:*expected-tui-command*)))
             (false (orrery/adapter:ecr-pass-p report))))
      (%cleanup-temp-tui-dir dir))))
