;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-fixture-generator-suite)

(defun %mk-temp-fixture-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-tui-fixtures-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(define-test (mcp-tui-fixture-generator-suite complete-mode-generates-all)
  (let ((dir (%mk-temp-fixture-dir "full")))
    (let ((res (orrery/adapter:generate-tui-fixture-set dir :complete)))
      (true (orrery/adapter:tfgr-pass-p res))
      (is = 24 (orrery/adapter:tfgr-generated-files res))
      (true (probe-file (orrery/adapter:scenario-artifact-path dir "T1" :asciicast))))))

(define-test (mcp-tui-fixture-generator-suite gapped-mode-omits-t6-cast)
  (let ((dir (%mk-temp-fixture-dir "gap")))
    (let ((res (orrery/adapter:generate-tui-fixture-set dir :gapped)))
      (true (orrery/adapter:tfgr-pass-p res))
      (is = 23 (orrery/adapter:tfgr-generated-files res))
      (false (probe-file (orrery/adapter:scenario-artifact-path dir "T6" :asciicast))))))
