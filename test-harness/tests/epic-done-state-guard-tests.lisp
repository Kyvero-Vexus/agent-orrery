;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic-done-state-guard-tests.lisp — Tests for Epic done-state denial guard
;;; Bead: agent-orrery-t5i

(in-package #:orrery/harness-tests)

(define-test epic-done-state-guard-suite)

(defun %mk-temp-gate-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-done-guard-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-gate (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-gate (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (epic-done-state-guard-suite epic4-deny-on-missing-s6)
  (let ((web (%mk-temp-gate-dir "web")))
    (unwind-protect
         (progn
           (%touch-gate (merge-pathnames "playwright-report.json" web) "S1 S2 S3 S4 S5")
           (%touch-gate (merge-pathnames "a.png" web) "png")
           (%touch-gate (merge-pathnames "a.zip" web) "zip")
           (let* ((res (orrery/adapter:evaluate-epic-done-state-guard :epic4 t web "cd e2e && ./run-e2e.sh"))
                  (json (orrery/adapter:epic-done-state-result->json res)))
             (false (orrery/adapter:edr-allowed-p res))
             (true (search "epic4-playwright-s1-s6-evidence-missing" json))
             (true (search "cd e2e && ./run-e2e.sh" json))))
      (%cleanup-gate web))))

(define-test (epic-done-state-guard-suite epic3-pass-with-valid-artifacts)
  (let ((tui (%mk-temp-gate-dir "tui")))
    (unwind-protect
         (progn
           (%touch-gate (merge-pathnames "tui-e2e-report.json" tui) "report")
           (%touch-gate (merge-pathnames "tui-e2e-session.cast" tui) "cast")
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-gate (merge-pathnames (format nil "~A-shot.png" sid) tui) "png")
             (%touch-gate (merge-pathnames (format nil "~A-transcript.txt" sid) tui) "txt"))
           (let ((res (orrery/adapter:evaluate-epic-done-state-guard :epic3 t tui "make e2e-tui")))
             (true (orrery/adapter:edr-allowed-p res))
             (true (search "\"allowed\":true" (orrery/adapter:epic-done-state-result->json res)))))
      (%cleanup-gate tui))))
