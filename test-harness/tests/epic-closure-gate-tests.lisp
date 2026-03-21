;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic-closure-gate-tests.lisp — Tests for Epic 3/4 closure gate
;;; Bead: agent-orrery-i9p

(in-package #:orrery/harness-tests)

(define-test epic-closure-gate-suite)

(defun %mk-temp-closure-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-closure-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %cleanup-closure-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %touch (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %seed-complete-tui (dir)
  (%touch (merge-pathnames "tui-e2e-report.json" dir) "report")
  (%touch (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%touch (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (epic-closure-gate-suite full-pass)
  (let ((web (%mk-temp-closure-dir "web-ok"))
        (tui (%mk-temp-closure-dir "tui-ok")))
    (unwind-protect
         (progn
           (%touch (merge-pathnames "e2e-report.json" web) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch (merge-pathnames (format nil "~A-shot.png" sid) web) "png")
             (%touch (merge-pathnames (format nil "~A-trace.zip" sid) web) "zip"))

           (%seed-complete-tui tui)

           (let* ((res (orrery/adapter:evaluate-epic34-closure-gate
                        web "cd e2e && ./run-e2e.sh"
                        tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:epic-closure-gate-result->json res)))
             (true (orrery/adapter:ecgr-overall-pass-p res))
             (true (search "\"overall_pass\":true" json))
             (true (search "\"blockers\":[]" json))
             (true (search "\"remediation_commands\":[]" json))))
      (%cleanup-closure-dir web)
      (%cleanup-closure-dir tui))))

(define-test (epic-closure-gate-suite fail-missing-web-s6)
  (let ((web (%mk-temp-closure-dir "web-fail"))
        (tui (%mk-temp-closure-dir "tui-fail")))
    (unwind-protect
         (progn
           (%touch (merge-pathnames "e2e-report.json" web) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5"))
             (%touch (merge-pathnames (format nil "~A-shot.png" sid) web) "png")
             (%touch (merge-pathnames (format nil "~A-trace.zip" sid) web) "zip"))

           (%seed-complete-tui tui)

           (let* ((res (orrery/adapter:evaluate-epic34-closure-gate
                        web "cd e2e && ./run-e2e.sh"
                        tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:epic-closure-gate-result->json res)))
             (false (orrery/adapter:ecgr-overall-pass-p res))
             (false (orrery/adapter:ecgr-epic4-pass-p res))
             (true (search "epic4-playwright-s1-s6-evidence-missing" json))
             (true (search "cd e2e && ./run-e2e.sh" json))))
      (%cleanup-closure-dir web)
      (%cleanup-closure-dir tui))))

(define-test (epic-closure-gate-suite fail-tui-notarization-command-mismatch)
  (let ((web (%mk-temp-closure-dir "web-ok-cmd"))
        (tui (%mk-temp-closure-dir "tui-cmd-fail")))
    (unwind-protect
         (progn
           (%touch (merge-pathnames "e2e-report.json" web) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch (merge-pathnames (format nil "~A-shot.png" sid) web) "png")
             (%touch (merge-pathnames (format nil "~A-trace.zip" sid) web) "zip"))
           (%seed-complete-tui tui)
           (let* ((res (orrery/adapter:evaluate-epic34-closure-gate
                        web "cd e2e && ./run-e2e.sh"
                        tui "make e2e-tui-t1-t6"))
                  (json (orrery/adapter:epic-closure-gate-result->json res)))
             (false (orrery/adapter:ecgr-overall-pass-p res))
             (false (orrery/adapter:ecgr-epic3-pass-p res))
             (true (search "epic3-mcp-tui-driver-command-mismatch" json))))
      (%cleanup-closure-dir web)
      (%cleanup-closure-dir tui))))

(define-test (epic-closure-gate-suite fail-tui-notarization-drift-mismatch)
  (let ((web (%mk-temp-closure-dir "web-ok-drift"))
        (tui (%mk-temp-closure-dir "tui-drift-current"))
        (baseline (%mk-temp-closure-dir "tui-drift-baseline")))
    (unwind-protect
         (progn
           (%touch (merge-pathnames "e2e-report.json" web) "report")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch (merge-pathnames (format nil "~A-shot.png" sid) web) "png")
             (%touch (merge-pathnames (format nil "~A-trace.zip" sid) web) "zip"))
           (%seed-complete-tui tui)
           (%seed-complete-tui baseline)
           (%touch (merge-pathnames "unexpected-drift.txt" tui) "drift")
           (let ((old-baseline (uiop:getenv "TUI_BASELINE_ARTIFACTS_DIR")))
             (unwind-protect
                  (progn
                    #+sbcl (sb-posix:setenv "TUI_BASELINE_ARTIFACTS_DIR" baseline 1)
                    (let* ((res (orrery/adapter:evaluate-epic34-closure-gate
                                 web "cd e2e && ./run-e2e.sh"
                                 tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                           (json (orrery/adapter:epic-closure-gate-result->json res)))
                      (false (orrery/adapter:ecgr-overall-pass-p res))
                      (false (orrery/adapter:ecgr-epic3-pass-p res))
                      (true (search "epic3-mcp-tui-driver-drift-mismatch" json))
                      (true (search "TUI_BASELINE_ARTIFACTS_DIR=<baseline-dir>" json))))
               (if old-baseline
                   #+sbcl (sb-posix:setenv "TUI_BASELINE_ARTIFACTS_DIR" old-baseline 1)
                   #+sbcl (sb-posix:unsetenv "TUI_BASELINE_ARTIFACTS_DIR")))))
      (%cleanup-closure-dir web)
      (%cleanup-closure-dir tui)
      (%cleanup-closure-dir baseline))))
