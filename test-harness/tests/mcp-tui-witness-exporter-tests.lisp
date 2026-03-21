;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-witness-exporter-suite)

(defun %mk-temp-witness-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-witness-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-witness-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-witness-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-witness-artifacts (dir)
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch-witness-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-witness-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) (format nil "tx-~A" sid))
    (%touch-witness-file (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%touch-witness-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (mcp-tui-witness-exporter-suite pass-on-complete-evidence)
  (let ((dir (%mk-temp-witness-dir "ok")))
    (unwind-protect
         (progn
           (%seed-witness-artifacts dir)
           (let* ((bundle (orrery/adapter:evaluate-mcp-tui-witness-bundle
                           dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:mcp-tui-witness-bundle->json bundle)))
             (true (orrery/adapter:mtwb-pass-p bundle))
             (true (orrery/adapter:mtwb-command-match-p bundle))
             (true (orrery/adapter:mtwb-closure-pass-p bundle))
             (is = 6 (length (orrery/adapter:mtwb-transcript-digest-map bundle)))
             (true (search "\"signature\"" json))))
      (%cleanup-witness-dir dir))))

(define-test (mcp-tui-witness-exporter-suite fail-on-command-drift)
  (let ((dir (%mk-temp-witness-dir "drift")))
    (unwind-protect
         (progn
           (%seed-witness-artifacts dir)
           (let* ((bundle (orrery/adapter:evaluate-mcp-tui-witness-bundle dir "cd e2e-tui && ./wrong.sh"))
                  (json (orrery/adapter:mcp-tui-witness-bundle->json bundle)))
             (false (orrery/adapter:mtwb-pass-p bundle))
             (false (orrery/adapter:mtwb-command-match-p bundle))
             (true (search "\"missing_scenarios\"" json))))
      (%cleanup-witness-dir dir))))
