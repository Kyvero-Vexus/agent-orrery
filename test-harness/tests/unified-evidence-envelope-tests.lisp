(in-package #:orrery/harness-tests)

(define-test unified-evidence-envelope-suite)

(defun %mk-temp-uee-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-uee-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-uee-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-uee-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-complete-web-uee (dir)
  (%touch-uee-file (merge-pathnames "e2e-report.json" dir) "report")
  (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
    (%touch-uee-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-uee-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip")))

(defun %seed-complete-tui-uee (dir)
  (%touch-uee-file (merge-pathnames "tui-e2e-report.json" dir) "report")
  (%touch-uee-file (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch-uee-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-uee-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch-uee-file (merge-pathnames (format nil "~A.cast" sid) dir) "cast")
    (%touch-uee-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (unified-evidence-envelope-suite pass-when-both-tracks-pass)
  (let ((web (%mk-temp-uee-dir "web-ok"))
        (tui (%mk-temp-uee-dir "tui-ok")))
    (unwind-protect
         (progn
           (%seed-complete-web-uee web)
           (%seed-complete-tui-uee tui)
           (let* ((bundle (orrery/adapter:evaluate-unified-preflight-bundle
                           web "cd e2e && ./run-e2e.sh"
                           tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (env (orrery/adapter:build-unified-evidence-envelope bundle))
                  (json (orrery/adapter:unified-evidence-envelope->json env)))
             (true (orrery/adapter:uee-pass-p env))
             (true (search "\"framework\":\"playwright\"" json))
             (true (search "\"framework\":\"mcp-tui-driver\"" json))
             (true (search "\"schema_version\":\"uee-v1\"" json))))
      (%cleanup-uee-dir web)
      (%cleanup-uee-dir tui))))

(define-test (unified-evidence-envelope-suite fail-when-tui-missing)
  (let ((web (%mk-temp-uee-dir "web-ok2"))
        (tui (%mk-temp-uee-dir "tui-bad")))
    (unwind-protect
         (progn
           (%seed-complete-web-uee web)
           (%seed-complete-tui-uee tui)
           (ignore-errors (delete-file (merge-pathnames "T6.cast" tui)))
           (let* ((bundle (orrery/adapter:evaluate-unified-preflight-bundle
                           web "cd e2e && ./run-e2e.sh"
                           tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (env (orrery/adapter:build-unified-evidence-envelope bundle))
                  (json (orrery/adapter:unified-evidence-envelope->json env)))
             (false (orrery/adapter:uee-pass-p env))
             (true (search "\"missing_scenarios\":[\"T6\"]" json))))
      (%cleanup-uee-dir web)
      (%cleanup-uee-dir tui))))
