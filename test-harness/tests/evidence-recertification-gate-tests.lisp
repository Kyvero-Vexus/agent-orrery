;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; evidence-recertification-gate-tests.lisp — Tests for release recertification gate
;;; Bead: agent-orrery-f15

(in-package #:orrery/harness-tests)

(define-test evidence-recertification-gate-suite)

(defun %mk-temp-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-recert-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-r (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-r (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-web (dir ids)
  (%touch-r (merge-pathnames "e2e-report.json" dir) "report")
  (dolist (sid ids)
    (%touch-r (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-r (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip")))

(defun %seed-tui (dir ids)
  (%touch-r (merge-pathnames "tui-e2e-report.json" dir) "report")
  (%touch-r (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid ids)
    (%touch-r (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-r (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch-r (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%touch-r (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (evidence-recertification-gate-suite recert-pass)
  (let ((ws (%mk-temp-dir "ws")) (wr (%mk-temp-dir "wr"))
        (ts (%mk-temp-dir "ts")) (tr (%mk-temp-dir "tr")))
    (unwind-protect
         (progn
           (%seed-web ws '("S1" "S2" "S3" "S4" "S5" "S6"))
           (%seed-web wr '("S1" "S2" "S3" "S4" "S5" "S6"))
           (%seed-tui ts '("T1" "T2" "T3" "T4" "T5" "T6"))
           (%seed-tui tr '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let ((res (orrery/adapter:evaluate-evidence-recertification-gate
                       ws wr ts tr
                       "cd e2e && ./run-e2e.sh"
                       "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:err-overall-pass-p res))
             (is = 0 (length (orrery/adapter:err-blockers res)))))
      (%cleanup-r ws) (%cleanup-r wr) (%cleanup-r ts) (%cleanup-r tr))))

(define-test (evidence-recertification-gate-suite recert-fails-mismatch)
  (let ((ws (%mk-temp-dir "wsf")) (wr (%mk-temp-dir "wrf"))
        (ts (%mk-temp-dir "tsf")) (tr (%mk-temp-dir "trf")))
    (unwind-protect
         (progn
           (%seed-web ws '("S1" "S2" "S3" "S4" "S5" "S6"))
           (%seed-web wr '("S1" "S2" "S3" "S4" "S5")) ; missing S6 in regenerated
           (%seed-tui ts '("T1" "T2" "T3" "T4" "T5" "T6"))
           (%seed-tui tr '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let ((res (orrery/adapter:evaluate-evidence-recertification-gate
                       ws wr ts tr
                       "cd e2e && ./run-e2e.sh"
                       "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (false (orrery/adapter:err-overall-pass-p res))
             (true (find "stored-vs-regenerated-evidence-mismatch"
                         (orrery/adapter:err-blockers res)
                         :test #'string=))))
      (%cleanup-r ws) (%cleanup-r wr) (%cleanup-r ts) (%cleanup-r tr))))
