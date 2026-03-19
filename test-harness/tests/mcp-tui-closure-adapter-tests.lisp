;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-closure-adapter-suite)

(defun %mk-temp-tui-closure-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-tui-closure-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-tui-closure-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-tui-closure-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (mcp-tui-closure-adapter-suite closure-pass)
  (let ((dir (%mk-temp-tui-closure-dir "ok")))
    (unwind-protect
         (progn
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-tui-closure-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-tui-closure-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
             (%touch-tui-closure-file (merge-pathnames (format nil "~A.cast" sid) dir) "cast")
             (%touch-tui-closure-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report"))
           (let ((r (orrery/adapter:evaluate-mcp-tui-closure-adapter dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:tcr-pass-p r))
             (is = 0 (length (orrery/adapter:tcr-gaps r)))))
      (%cleanup-tui-closure-dir dir))))

(define-test (mcp-tui-closure-adapter-suite closure-fails-with-gaps)
  (let ((dir (%mk-temp-tui-closure-dir "fail")))
    (unwind-protect
         (progn
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-tui-closure-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-tui-closure-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt"))
           (let ((r (orrery/adapter:evaluate-mcp-tui-closure-adapter dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (false (orrery/adapter:tcr-pass-p r))
             (true (> (length (orrery/adapter:tcr-gaps r)) 0))
             (true (search "\"gaps\"" (orrery/adapter:tui-closure-report->json r)))))
      (%cleanup-tui-closure-dir dir))))
