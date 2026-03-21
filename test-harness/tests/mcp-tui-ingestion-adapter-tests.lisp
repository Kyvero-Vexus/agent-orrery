;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-ingestion-adapter-suite)

(defun %mk-temp-ingest-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-tui-ingest-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-ingest-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-ingest-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-complete-t1-t6-artifacts (dir)
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch-ingest-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-ingest-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch-ingest-file (merge-pathnames (format nil "~A.cast" sid) dir) "cast")
    (%touch-ingest-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (mcp-tui-ingestion-adapter-suite pass-with-complete-evidence)
  (let ((dir (%mk-temp-ingest-dir "ok")))
    (unwind-protect
         (progn
           (%seed-complete-t1-t6-artifacts dir)
           (let ((r (orrery/adapter:evaluate-mcp-tui-ingestion-adapter
                     dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:mtir-pass-p r))
             (true (orrery/adapter:mtir-command-match-p r))
             (is = 0 (length (orrery/adapter:mtir-missing-scenarios r)))
             (true (search "\"required_runner\":\"mcp-tui-driver\""
                           (orrery/adapter:mcp-tui-ingestion-result->json r)))
             (true (search "\"command_hash\":"
                           (orrery/adapter:mcp-tui-ingestion-result->json r)))))
      (%cleanup-ingest-dir dir))))

(define-test (mcp-tui-ingestion-adapter-suite fail-command-drift)
  (let ((dir (%mk-temp-ingest-dir "cmd")))
    (unwind-protect
         (progn
           (%seed-complete-t1-t6-artifacts dir)
           (let ((r (orrery/adapter:evaluate-mcp-tui-ingestion-adapter dir "make e2e-tui")))
             (false (orrery/adapter:mtir-pass-p r))
             (false (orrery/adapter:mtir-command-match-p r))))
      (%cleanup-ingest-dir dir))))

(define-test (mcp-tui-ingestion-adapter-suite fail-missing-artifacts)
  (let ((dir (%mk-temp-ingest-dir "missing")))
    (unwind-protect
         (progn
           (%seed-complete-t1-t6-artifacts dir)
           (delete-file (merge-pathnames "T4.cast" dir))
           (let* ((r (orrery/adapter:evaluate-mcp-tui-ingestion-adapter
                      dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:mcp-tui-ingestion-result->json r)))
             (false (orrery/adapter:mtir-pass-p r))
             (true (find "T4" (orrery/adapter:mtir-missing-scenarios r) :test #'string=))
             (true (search "\"missing_artifact_kinds\":[\"asciicast\"]" json))))
      (%cleanup-ingest-dir dir))))
