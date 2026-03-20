;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-artifact-notarizer-tests.lisp — Tests for T1-T6 artifact notarizer + drift diff
;;; Bead: agent-orrery-l71w

(in-package #:orrery/harness-tests)

(define-test mcp-tui-artifact-notarizer-suite)

(defun %mk-temp-notary-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-tui-notary-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-notary-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-notary-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-complete-t1-t6 (dir)
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch-notary-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-notary-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch-notary-file (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%touch-notary-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (mcp-tui-artifact-notarizer-suite pass-when-complete-and-no-drift)
  (let ((baseline (%mk-temp-notary-dir "baseline"))
        (current (%mk-temp-notary-dir "current")))
    (unwind-protect
         (progn
           (%seed-complete-t1-t6 baseline)
           (%seed-complete-t1-t6 current)
           (let ((note (orrery/adapter:notarize-mcp-tui-artifacts
                        current
                        "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
                        baseline)))
             (true (orrery/adapter:mtan-pass-p note))
             (true (orrery/adapter:mtan-command-match-p note))
             (true (orrery/adapter:mtan-drift-pass-p note))
             (is = 0 (orrery/adapter:mtan-drift-mismatch-count note))
             (true (> (orrery/adapter:mtan-environment-fingerprint note) 0))))
      (%cleanup-notary-dir baseline)
      (%cleanup-notary-dir current))))

(define-test (mcp-tui-artifact-notarizer-suite fail-when-drift-detected)
  (let ((baseline (%mk-temp-notary-dir "baseline-drift"))
        (current (%mk-temp-notary-dir "current-drift")))
    (unwind-protect
         (progn
           (%seed-complete-t1-t6 baseline)
           (%seed-complete-t1-t6 current)
           (ignore-errors (delete-file (merge-pathnames "T6-report.json" current)))
           (let ((note (orrery/adapter:notarize-mcp-tui-artifacts
                        current
                        "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
                        baseline)))
             (false (orrery/adapter:mtan-pass-p note))
             (false (orrery/adapter:mtan-drift-pass-p note))
             (true (> (orrery/adapter:mtan-drift-mismatch-count note) 0))))
      (%cleanup-notary-dir baseline)
      (%cleanup-notary-dir current))))
