;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test playwright-fixture-synthesizer-suite)

(defun %mk-temp-playwright-fixture-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-playwright-fixtures-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(define-test (playwright-fixture-synthesizer-suite complete-mode-generates-all)
  (let ((dir (%mk-temp-playwright-fixture-dir "full")))
    (let ((res (orrery/adapter:generate-playwright-fixture-set dir :complete)))
      (true (orrery/adapter:pfgr-pass-p res))
      (is = 20 (orrery/adapter:pfgr-generated-files res))
      (true (probe-file (orrery/adapter:playwright-scenario-artifact-path dir "S1" :trace)))
      (true (probe-file (orrery/adapter:playwright-command-transcript-path dir))))))

(define-test (playwright-fixture-synthesizer-suite missing-trace-mode-omits-s6-trace)
  (let ((dir (%mk-temp-playwright-fixture-dir "gap")))
    (let ((res (orrery/adapter:generate-playwright-fixture-set dir :missing-trace)))
      (true (orrery/adapter:pfgr-pass-p res))
      (is = 19 (orrery/adapter:pfgr-generated-files res))
      (false (probe-file (orrery/adapter:playwright-scenario-artifact-path dir "S6" :trace))))))

(define-test (playwright-fixture-synthesizer-suite missing-scenario-mode-omits-s6-all-artifacts)
  (let ((dir (%mk-temp-playwright-fixture-dir "missing-scenario")))
    (let ((res (orrery/adapter:generate-playwright-fixture-set dir :missing-scenario)))
      (true (orrery/adapter:pfgr-pass-p res))
      (is = 17 (orrery/adapter:pfgr-generated-files res))
      (false (probe-file (orrery/adapter:playwright-scenario-artifact-path dir "S6" :screenshot)))
      (false (probe-file (orrery/adapter:playwright-scenario-artifact-path dir "S6" :trace)))
      (false (probe-file (orrery/adapter:playwright-scenario-artifact-path dir "S6" :transcript))))))
