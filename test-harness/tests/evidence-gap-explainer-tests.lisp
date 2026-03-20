;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; evidence-gap-explainer-tests.lisp — tests for closure-gate evidence-gap explainer
;;; Bead: agent-orrery-fdtj

(in-package #:orrery/harness-tests)

(define-test evidence-gap-explainer-suite)

(defun %mk-temp-ege-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-ege-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %cleanup-ege-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %touch-ege (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %seed-web-ok (dir)
  (%touch-ege (merge-pathnames "e2e-report.json" dir) "report")
  (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
    (%touch-ege (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-ege (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip")))

(defun %seed-tui-ok (dir)
  (%touch-ege (merge-pathnames "tui-e2e-report.json" dir) "report")
  (%touch-ege (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch-ege (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-ege (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch-ege (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%touch-ege (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (evidence-gap-explainer-suite pass-when-both-frameworks-complete)
  (let ((web (%mk-temp-ege-dir "web-pass"))
        (tui (%mk-temp-ege-dir "tui-pass")))
    (unwind-protect
         (progn
           (%seed-web-ok web)
           (%seed-tui-ok tui)
           (let ((res (orrery/adapter:explain-epic34-evidence-gaps
                       web "cd e2e && ./run-e2e.sh"
                       tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:ege-pass-p res))
             (true (orrery/adapter:ege-web-pass-p res))
             (true (orrery/adapter:ege-tui-pass-p res))
             (equal 0 (length (orrery/adapter:ege-blockers res)))
             (search "\"pass\":true"
                     (orrery/adapter:evidence-gap-explanation->json res))))
      (%cleanup-ege-dir web)
      (%cleanup-ege-dir tui))))

(define-test (evidence-gap-explainer-suite emits-remediation-for-web-gaps)
  (let ((web (%mk-temp-ege-dir "web-fail"))
        (tui (%mk-temp-ege-dir "tui-ok")))
    (unwind-protect
         (progn
           (%touch-ege (merge-pathnames "e2e-report.json" web) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5"))
             (%touch-ege (merge-pathnames (format nil "~A-shot.png" sid) web) "png")
             (%touch-ege (merge-pathnames (format nil "~A-trace.zip" sid) web) "zip"))
           (%seed-tui-ok tui)
           (let* ((res (orrery/adapter:explain-epic34-evidence-gaps
                        web "cd e2e && ./run-e2e.sh"
                        tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:evidence-gap-explanation->json res)))
             (false (orrery/adapter:ege-pass-p res))
             (false (orrery/adapter:ege-web-pass-p res))
             (true (orrery/adapter:ege-tui-pass-p res))
             (true (plusp (length (orrery/adapter:ege-blockers res))))
             (true (search "run-e2e.sh" json))
             (true (search "missing-scenario" json))))
      (%cleanup-ege-dir web)
      (%cleanup-ege-dir tui))))
