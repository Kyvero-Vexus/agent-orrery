;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-scorecard-gate-suite)

(defun %mk-temp-tui-scorecard-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-tui-score-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-tui-scorecard-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-tui-scorecard-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (mcp-tui-scorecard-gate-suite scorecard-pass)
  (let ((dir (%mk-temp-tui-scorecard-dir "ok")))
    (unwind-protect
         (progn
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-tui-scorecard-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-tui-scorecard-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
             (%touch-tui-scorecard-file (merge-pathnames (format nil "~A.cast" sid) dir) "cast")
             (%touch-tui-scorecard-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report"))
           (let ((r (orrery/adapter:evaluate-mcp-tui-scorecard-gate dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:mtsr-pass-p r))
             (is = 0 (length (orrery/adapter:mtsr-missing-scenarios r)))
             (true (search "\"scenarios\"" (orrery/adapter:mcp-tui-scorecard-result->detailed-json r)))
             (true (search "\"T1\"" (orrery/adapter:mcp-tui-scorecard-result->detailed-json r)))))
      (%cleanup-tui-scorecard-dir dir))))

(define-test (mcp-tui-scorecard-gate-suite scorecard-fails-command-drift)
  (let ((dir (%mk-temp-tui-scorecard-dir "cmd")))
    (unwind-protect
         (progn
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-tui-scorecard-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-tui-scorecard-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
             (%touch-tui-scorecard-file (merge-pathnames (format nil "~A.cast" sid) dir) "cast")
             (%touch-tui-scorecard-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report"))
           (let ((r (orrery/adapter:evaluate-mcp-tui-scorecard-gate dir "make e2e-tui")))
             (false (orrery/adapter:mtsr-pass-p r))
             (false (orrery/adapter:mtsr-command-match-p r))))
      (%cleanup-tui-scorecard-dir dir))))

(define-test (mcp-tui-scorecard-gate-suite scorecard-detailed-json-includes-scenarios)
  (let ((dir (%mk-temp-tui-scorecard-dir "json")))
    (unwind-protect
         (progn
           (%touch-tui-scorecard-file (merge-pathnames "T1-shot.png" dir) "png")
           (%touch-tui-scorecard-file (merge-pathnames "T1-transcript.txt" dir) "txt")
           (%touch-tui-scorecard-file (merge-pathnames "T1.cast" dir) "cast")
           (%touch-tui-scorecard-file (merge-pathnames "T1-report.json" dir) "report")
           (let* ((r (orrery/adapter:evaluate-mcp-tui-scorecard-gate dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:mcp-tui-scorecard-result->detailed-json r)))
             (true (search "\"required_runner\":\"mcp-tui-driver\"" json))
             (true (search "\"deterministic_command\":\"cd e2e-tui && ./run-tui-e2e-t1-t6.sh\"" json))
             (true (search "\"scenarios\":[{" json))
             (true (search "\"id\":\"T1\"" json))
             (true (search "\"missing_scenarios\":[\"T2\"" json))))
      (%cleanup-tui-scorecard-dir dir))))
