;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-unified-envelope-projector-suite)

(defun %mk-temp-envelope-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-tui-env-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-envelope-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-envelope-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-complete-envelope-artifacts (dir)
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch-envelope-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-envelope-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch-envelope-file (merge-pathnames (format nil "~A.cast" sid) dir) "cast")
    (%touch-envelope-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (mcp-tui-unified-envelope-projector-suite pass-complete)
  (let ((dir (%mk-temp-envelope-dir "ok")))
    (unwind-protect
         (progn
           (%seed-complete-envelope-artifacts dir)
           (let ((rep (orrery/adapter:project-mcp-tui-unified-envelope
                       dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:mtep-pass-p rep))
             (true (search "\"command_hash\":" (orrery/adapter:mcp-tui-envelope-report->json rep)))))
      (%cleanup-envelope-dir dir))))

(define-test (mcp-tui-unified-envelope-projector-suite fail-command-drift-taxonomy)
  (let ((dir (%mk-temp-envelope-dir "drift")))
    (unwind-protect
         (progn
           (%seed-complete-envelope-artifacts dir)
           (let* ((rep (orrery/adapter:project-mcp-tui-unified-envelope dir "make e2e-tui"))
                  (json (orrery/adapter:mcp-tui-envelope-report->json rep)))
             (false (orrery/adapter:mtep-pass-p rep))
             (true (search "command-drift" json))))
      (%cleanup-envelope-dir dir))))
