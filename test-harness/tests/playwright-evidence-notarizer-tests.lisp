;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-notarizer-tests.lisp — Tests for Playwright evidence notarizer
;;; Bead: agent-orrery-bcq9

(in-package #:orrery/harness-tests)

(define-test playwright-evidence-notarizer-suite)

(defun %mk-web-notary-dir (prefix)
  (let ((d (format nil "/tmp/orrery-web-notary-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %touch-web-notary (p c)
  (with-open-file (s p :direction :output :if-exists :supersede)
    (write-string c s)))

(defun %cleanup-web-notary (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

(define-test (playwright-evidence-notarizer-suite complete-notarization)
  (let ((d (%mk-web-notary-dir "ok")))
    (unwind-protect
         (progn
           (%touch-web-notary (merge-pathnames "playwright-report.json" d) "S1 S2 S3 S4 S5 S6")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-web-notary (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-web-notary (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let ((n (orrery/adapter:write-playwright-evidence-notarization d "cd e2e && ./run-e2e.sh")))
             (true n)
             (true (orrery/adapter:pen-complete-p n))
             (is = 6 (orrery/adapter:pen-scenario-count n))
             (is = 0 (length (orrery/adapter:pen-missing-scenarios n)))
             (true (plusp (length (orrery/adapter:pen-chain-digest n))))
             (true (probe-file (merge-pathnames "playwright-evidence-notarization.json" d)))))
      (%cleanup-web-notary d))))

(define-test (playwright-evidence-notarizer-suite fail-closed-missing-scenarios)
  (let ((d (%mk-web-notary-dir "missing")))
    (unwind-protect
         (progn
           (%touch-web-notary (merge-pathnames "playwright-report.json" d) "S1")
           (%touch-web-notary (merge-pathnames "s1-screenshot.png" d) "png")
           (%touch-web-notary (merge-pathnames "s1-trace.zip" d) "zip")
           (let ((n (orrery/adapter:notarize-playwright-evidence d "cd e2e && ./run-e2e.sh")))
             (false (orrery/adapter:pen-complete-p n))
             (true (find "S6" (orrery/adapter:pen-missing-scenarios n) :test #'string=))))
      (%cleanup-web-notary d))))
