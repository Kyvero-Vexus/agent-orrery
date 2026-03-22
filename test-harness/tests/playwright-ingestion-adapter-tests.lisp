(in-package #:orrery/harness-tests)

(define-test playwright-ingestion-adapter-suite)

(defun %mk-temp-web-ingest-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-web-ingest-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-web-ingest-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-web-ingest-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-complete-s1-s6-web-artifacts (dir)
  (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
    (%touch-web-ingest-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-web-ingest-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip")
    (%touch-web-ingest-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (playwright-ingestion-adapter-suite pass-with-complete-evidence)
  (let ((dir (%mk-temp-web-ingest-dir "ok")))
    (unwind-protect
         (progn
           (%seed-complete-s1-s6-web-artifacts dir)
           (let ((r (orrery/adapter:evaluate-playwright-ingestion-adapter
                     dir "cd e2e && ./run-e2e.sh")))
             (true (orrery/adapter:pwir-pass-p r))
             (true (orrery/adapter:pwir-command-match-p r))
             (is = 0 (length (orrery/adapter:pwir-missing-scenarios r)))
             (true (search "\"required_runner\":\"playwright\""
                           (orrery/adapter:playwright-ingestion-result->json r)))
             (true (search "\"command_hash\":"
                           (orrery/adapter:playwright-ingestion-result->json r)))))
      (%cleanup-web-ingest-dir dir))))

(define-test (playwright-ingestion-adapter-suite fails-on-missing-s6-and-command-drift)
  (let ((dir (%mk-temp-web-ingest-dir "bad")))
    (unwind-protect
         (progn
           (%seed-complete-s1-s6-web-artifacts dir)
           (ignore-errors (delete-file (merge-pathnames "S6-trace.zip" dir)))
           (let ((r (orrery/adapter:evaluate-playwright-ingestion-adapter dir "make e2e")))
             (false (orrery/adapter:pwir-pass-p r))
             (false (orrery/adapter:pwir-command-match-p r))
             (true (find "S6" (orrery/adapter:pwir-missing-scenarios r) :test #'string=))
             (true (search "\"missing_scenarios\":[\"S6\"]"
                           (orrery/adapter:playwright-ingestion-result->json r)))))
      (%cleanup-web-ingest-dir dir))))
