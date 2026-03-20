;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-replay-verdict-emitter-suite)

(defun %mk-temp-replay-verdict-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-replay-verdict-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-replay-verdict-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-replay-verdict-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (mcp-tui-replay-verdict-emitter-suite pass-with-complete-artifacts)
  (let ((dir (%mk-temp-replay-verdict-dir "ok")))
    (unwind-protect
         (progn
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-replay-verdict-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-replay-verdict-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
             (%touch-replay-verdict-file (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
             (%touch-replay-verdict-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report"))
           (let ((v (orrery/adapter:evaluate-mcp-tui-replay-verdict dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:mtrv-pass-p v))
             (true (search "\"rows\"" (orrery/adapter:mcp-tui-replay-verdict->json v)))))
      (%cleanup-replay-verdict-dir dir))))
