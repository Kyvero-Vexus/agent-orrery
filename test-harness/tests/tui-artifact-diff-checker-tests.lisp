;;; tui-artifact-diff-checker-tests.lisp
(in-package #:orrery/harness-tests)

(define-test tui-artifact-diff-checker-suite)

(defun %mk-temp-diff-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-diff-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-diff (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-diff (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (tui-artifact-diff-checker-suite pass-when-equal)
  (let ((a (%mk-temp-diff-dir "a")) (b (%mk-temp-diff-dir "b")))
    (unwind-protect
         (progn
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-diff (merge-pathnames (format nil "~A-shot.png" sid) a) "png")
             (%touch-diff (merge-pathnames (format nil "~A-transcript.txt" sid) a) "txt")
             (%touch-diff (merge-pathnames (format nil "~A-shot.png" sid) b) "png")
             (%touch-diff (merge-pathnames (format nil "~A-transcript.txt" sid) b) "txt"))
           (%touch-diff (merge-pathnames "tui-e2e-report.json" a) "report")
           (%touch-diff (merge-pathnames "tui-e2e-session.cast" a) "cast")
           (%touch-diff (merge-pathnames "tui-e2e-report.json" b) "report")
           (%touch-diff (merge-pathnames "tui-e2e-session.cast" b) "cast")
           (let ((r (orrery/adapter:compare-tui-artifact-bundles a b)))
             (true (orrery/adapter:tdr-pass-p r))
             (is = 0 (orrery/adapter:tdr-mismatch-count r))))
      (%cleanup-diff a) (%cleanup-diff b))))

(define-test (tui-artifact-diff-checker-suite fail-on-missing)
  (let ((a (%mk-temp-diff-dir "ax")) (b (%mk-temp-diff-dir "bx")))
    (unwind-protect
         (progn
           (%touch-diff (merge-pathnames "T1-shot.png" a) "png")
           (%touch-diff (merge-pathnames "T1-transcript.txt" a) "txt")
           ;; current missing transcript
           (%touch-diff (merge-pathnames "T1-shot.png" b) "png")
           (let ((r (orrery/adapter:compare-tui-artifact-bundles a b)))
             (false (orrery/adapter:tdr-pass-p r))
             (true (> (orrery/adapter:tdr-mismatch-count r) 0))))
      (%cleanup-diff a) (%cleanup-diff b))))
