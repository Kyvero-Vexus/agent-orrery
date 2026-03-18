;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-scenario-ledger-tests.lisp — Tests for T1-T6 rerun ledger continuity
;;; Bead: agent-orrery-h9i

(in-package #:orrery/harness-tests)

(define-test tui-scenario-ledger-suite)

(defun %mk-temp-ledger-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-tui-ledger-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %cleanup-temp-ledger-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %touch-ledger-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %seed-tui-artifacts (dir &key (mutate-t3 nil))
  (%touch-ledger-file (merge-pathnames "tui-e2e-report.json" dir) "report")
  (%touch-ledger-file (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch-ledger-file (merge-pathnames (format nil "~A-shot.png" sid) dir)
                        (if (and mutate-t3 (string= sid "T3")) "png-mutated" "png"))
    (%touch-ledger-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir)
                        (if (and mutate-t3 (string= sid "T3")) "txt-mutated" "txt"))))

(define-test (tui-scenario-ledger-suite baseline-establishes-attestations)
  (let* ((dir (%mk-temp-ledger-dir "baseline"))
         (ledger-json (namestring (merge-pathnames "t1-t6-ledger.json" dir)))
         (ledger-sexp (format nil "~A.sexp" ledger-json)))
    (unwind-protect
         (progn
           (%seed-tui-artifacts dir)
           (let ((ledger (orrery/adapter:write-tui-scenario-ledger
                          dir
                          "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
                          ledger-json
                          :previous-ledger-path ledger-sexp)))
             (true (orrery/adapter:tsl-continuity-pass-p ledger))
             (is = 6 (length (orrery/adapter:tsl-scenario-attestations ledger)))))
      (%cleanup-temp-ledger-dir dir))))

(define-test (tui-scenario-ledger-suite rerun-mismatch-fails)
  (let* ((dir (%mk-temp-ledger-dir "mismatch"))
         (ledger-json (namestring (merge-pathnames "t1-t6-ledger.json" dir)))
         (ledger-sexp (format nil "~A.sexp" ledger-json)))
    (unwind-protect
         (progn
           (%seed-tui-artifacts dir)
           (orrery/adapter:write-tui-scenario-ledger
            dir
            "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
            ledger-json
            :previous-ledger-path ledger-sexp)
           (%seed-tui-artifacts dir :mutate-t3 t)
           (let ((ledger (orrery/adapter:write-tui-scenario-ledger
                          dir
                          "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
                          ledger-json
                          :previous-ledger-path ledger-sexp)))
             (false (orrery/adapter:tsl-continuity-pass-p ledger))
             (let ((row (find "T3"
                              (orrery/adapter:tsl-scenario-attestations ledger)
                              :key #'orrery/adapter:sra-scenario-id
                              :test #'string=)))
               (false (orrery/adapter:sra-continuity-pass-p row)))))
      (%cleanup-temp-ledger-dir dir))))
