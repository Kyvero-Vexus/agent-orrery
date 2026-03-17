;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic-closure-gate-tests.lisp — Tests for Epic 3/4 closure gate
;;; Bead: agent-orrery-i9p

(in-package #:orrery/harness-tests)

(define-test epic-closure-gate-suite)

(defun %mk-temp-closure-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-closure-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %cleanup-closure-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %touch (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(define-test (epic-closure-gate-suite full-pass)
  (let ((web (%mk-temp-closure-dir "web-ok"))
        (tui (%mk-temp-closure-dir "tui-ok")))
    (unwind-protect
         (progn
           (%touch (merge-pathnames "e2e-report.json" web) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch (merge-pathnames (format nil "~A-shot.png" sid) web) "png")
             (%touch (merge-pathnames (format nil "~A-trace.zip" sid) web) "zip"))

           (%touch (merge-pathnames "tui-e2e-report.json" tui) "report")
           (%touch (merge-pathnames "tui-e2e-session.cast" tui) "cast")
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch (merge-pathnames (format nil "~A-shot.png" sid) tui) "png")
             (%touch (merge-pathnames (format nil "~A-transcript.txt" sid) tui) "txt"))

           (let ((res (orrery/adapter:evaluate-epic34-closure-gate web "cd e2e && ./run-e2e.sh" tui "make e2e-tui")))
             (true (orrery/adapter:ecgr-overall-pass-p res))
             (true (search "\"overall_pass\":true" (orrery/adapter:epic-closure-gate-result->json res)))))
      (%cleanup-closure-dir web)
      (%cleanup-closure-dir tui))))

(define-test (epic-closure-gate-suite fail-missing-web-s6)
  (let ((web (%mk-temp-closure-dir "web-fail"))
        (tui (%mk-temp-closure-dir "tui-fail")))
    (unwind-protect
         (progn
           (%touch (merge-pathnames "e2e-report.json" web) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5"))
             (%touch (merge-pathnames (format nil "~A-shot.png" sid) web) "png")
             (%touch (merge-pathnames (format nil "~A-trace.zip" sid) web) "zip"))

           (%touch (merge-pathnames "tui-e2e-report.json" tui) "report")
           (%touch (merge-pathnames "tui-e2e-session.cast" tui) "cast")
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch (merge-pathnames (format nil "~A-shot.png" sid) tui) "png")
             (%touch (merge-pathnames (format nil "~A-transcript.txt" sid) tui) "txt"))

           (let ((res (orrery/adapter:evaluate-epic34-closure-gate web "cd e2e && ./run-e2e.sh" tui "make e2e-tui")))
             (false (orrery/adapter:ecgr-overall-pass-p res))
             (false (orrery/adapter:ecgr-epic4-pass-p res))))
      (%cleanup-closure-dir web)
      (%cleanup-closure-dir tui))))
