;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; protocol-evidence-matrix-tests.lisp — Tests for protocol/evidence matrix gate
;;; Bead: agent-orrery-i944

(in-package #:orrery/harness-tests)

(define-test protocol-evidence-matrix-suite)

(defun %pem-mk-temp-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-pem-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %pem-touch (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %pem-cleanup (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %pem-seed-web (dir ids)
  (%pem-touch (merge-pathnames "e2e-report.json" dir) "report")
  (dolist (sid ids)
    (%pem-touch (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%pem-touch (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip")))

(defun %pem-seed-tui (dir ids)
  (%pem-touch (merge-pathnames "tui-e2e-report.json" dir) "report")
  (%pem-touch (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid ids)
    (%pem-touch (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%pem-touch (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%pem-touch (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%pem-touch (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (protocol-evidence-matrix-suite matrix-pass)
  (let ((web (%pem-mk-temp-dir "web-ok"))
        (tui (%pem-mk-temp-dir "tui-ok")))
    (unwind-protect
         (progn
           (%pem-seed-web web '("S1" "S2" "S3" "S4" "S5" "S6"))
           (%pem-seed-tui tui '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let ((res (orrery/adapter:evaluate-protocol-evidence-matrix
                       web "cd e2e && ./run-e2e.sh"
                       tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (true (orrery/adapter:pmrep-overall-pass-p res))
             (true (search "\"overall_pass\":true"
                           (orrery/adapter:protocol-matrix-report->json res)))))
      (%pem-cleanup web)
      (%pem-cleanup tui))))

(define-test (protocol-evidence-matrix-suite matrix-fail-missing-epic4-evidence)
  (let ((web (%pem-mk-temp-dir "web-fail"))
        (tui (%pem-mk-temp-dir "tui-ok2")))
    (unwind-protect
         (progn
           (%pem-seed-web web '("S1" "S2" "S3" "S4" "S5"))
           (%pem-seed-tui tui '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let ((res (orrery/adapter:evaluate-protocol-evidence-matrix
                       web "cd e2e && ./run-e2e.sh"
                       tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
             (false (orrery/adapter:pmrep-overall-pass-p res))
             (false (orrery/adapter:pmrep-epic4-pass-p res))))
      (%pem-cleanup web)
      (%pem-cleanup tui))))
