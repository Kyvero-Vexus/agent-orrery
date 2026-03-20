;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; protocol-evidence-gap-explainer-tests.lisp — tests for deterministic evidence-gap diagnostics
;;; Bead: agent-orrery-fdtj

(in-package #:orrery/harness-tests)

(define-test protocol-evidence-gap-explainer-suite)

(defun %peg-mk-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-peg-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %peg-touch (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %peg-clean (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %peg-seed-web (dir ids)
  (%peg-touch (merge-pathnames "e2e-report.json" dir) "report")
  (dolist (sid ids)
    (%peg-touch (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%peg-touch (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip")))

(defun %peg-seed-tui (dir ids)
  (%peg-touch (merge-pathnames "tui-e2e-report.json" dir) "report")
  (%peg-touch (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid ids)
    (%peg-touch (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%peg-touch (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%peg-touch (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%peg-touch (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (protocol-evidence-gap-explainer-suite no-gaps-when-complete)
  (let ((web (%peg-mk-dir "web-ok"))
        (tui (%peg-mk-dir "tui-ok")))
    (unwind-protect
         (progn
           (%peg-seed-web web '("S1" "S2" "S3" "S4" "S5" "S6"))
           (%peg-seed-tui tui '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let ((res (orrery/adapter:explain-protocol-evidence-gaps
                       web "cd e2e && ./run-e2e.sh"
                       tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:pegr-closure-pass-p res))
             (is = 0 (length (orrery/adapter:pegr-gaps res)))))
      (%peg-clean web)
      (%peg-clean tui))))

(define-test (protocol-evidence-gap-explainer-suite emits-epic4-remediation-on-missing-s6)
  (let ((web (%peg-mk-dir "web-gap"))
        (tui (%peg-mk-dir "tui-ok2")))
    (unwind-protect
         (progn
           (%peg-seed-web web '("S1" "S2" "S3" "S4" "S5"))
           (%peg-seed-tui tui '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let ((res (orrery/adapter:explain-protocol-evidence-gaps
                       web "cd e2e && ./run-e2e.sh"
                       tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (false (orrery/adapter:pegr-closure-pass-p res))
             (true (find "epic4-playwright-s1-s6-evidence-missing"
                         (orrery/adapter:pegr-gaps res)
                         :test #'string=))
             (true (search "Playwright"
                           (orrery/adapter:protocol-evidence-gap-report->json res)))))
      (%peg-clean web)
      (%peg-clean tui))))

(define-test (protocol-evidence-gap-explainer-suite remediation-commands-are-canonical)
  (let ((web (%peg-mk-dir "web-gap2"))
        (tui (%peg-mk-dir "tui-gap2")))
    (unwind-protect
         (progn
           (%peg-seed-web web '("S1"))
           (%peg-seed-tui tui '("T1"))
           (let* ((res (orrery/adapter:explain-protocol-evidence-gaps
                        web "cd e2e && ./run-e2e.sh"
                        tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:protocol-evidence-gap-report->json res)))
             (false (orrery/adapter:pegr-closure-pass-p res))
             (true (search "cd e2e && ./run-e2e.sh" json))
             (true (search "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" json))))
      (%peg-clean web)
      (%peg-clean tui))))
