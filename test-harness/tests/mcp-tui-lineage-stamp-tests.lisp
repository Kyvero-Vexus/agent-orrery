;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-lineage-stamp-suite)

(defun %mk-temp-lineage-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-mtls-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-lineage-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-lineage-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-lineage-fixtures (dir ids)
  (dolist (sid ids)
    (%touch-lineage-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-lineage-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch-lineage-file (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%touch-lineage-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (mcp-tui-lineage-stamp-suite pass-with-complete-t1-t6)
  (let ((dir (%mk-temp-lineage-dir "ok")))
    (unwind-protect
         (progn
           (%seed-lineage-fixtures dir '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let* ((stamp (orrery/adapter:evaluate-mcp-tui-lineage-stamp
                          dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:mcp-tui-lineage-stamp->json stamp)))
             (true (orrery/adapter:mtls-pass-p stamp))
             (true (search "\"transcript_chain_digest\":" json))
             (true (search "\"command_hash\":" json))
             (true (search "\"artifact_checksums\":{" json))
             (true (search "\"missing_scenarios\":[]" json))))
      (%cleanup-lineage-dir dir))))

(define-test (mcp-tui-lineage-stamp-suite fail-closed-on-command-drift-or-missing)
  (let ((dir (%mk-temp-lineage-dir "missing")))
    (unwind-protect
         (progn
           (%seed-lineage-fixtures dir '("T1" "T2" "T3" "T4" "T5"))
           (let* ((stamp (orrery/adapter:evaluate-mcp-tui-lineage-stamp dir "make tui-e2e"))
                  (json (orrery/adapter:mcp-tui-lineage-stamp->json stamp)))
             (false (orrery/adapter:mtls-pass-p stamp))
             (false (orrery/adapter:mtls-command-match-p stamp))
             (true (search "\"missing_scenarios\":[\"T6\"]" json))))
      (%cleanup-lineage-dir dir))))
