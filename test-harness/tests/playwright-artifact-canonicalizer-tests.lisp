;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-artifact-canonicalizer-tests.lisp — Tests for S1-S6 artifact canonicalizer + preflight
;;; Bead: agent-orrery-bt9

(in-package #:orrery/harness-tests)

(define-test playwright-artifact-canonicalizer-suite)

;; normalize-path-slashes replaces backslashes
(define-test (playwright-artifact-canonicalizer-suite normalize-path-slashes)
  (is string= "foo/bar/baz"
      (orrery/adapter:normalize-path-slashes "foo\\bar\\baz"))
  (is string= "/tmp/screen.png"
      (orrery/adapter:normalize-path-slashes "/tmp/screen.png")))

;; Empty dir => all S1-S6 missing => canonicalization-report pass=false
(define-test (playwright-artifact-canonicalizer-suite empty-dir-all-missing)
  (let* ((d (format nil "/tmp/orrery-canon-~D/" (get-universal-time)))
         (report (progn
                   (ensure-directories-exist (merge-pathnames "dummy" d))
                   (orrery/adapter:build-playwright-canonicalization-report d))))
    (unwind-protect
         (progn
           (false (orrery/adapter:pcr-pass-p report))
           (true (>= (length (orrery/adapter:pcr-missing-scenarios report)) 1)))
      (when (probe-file d)
        (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
          (ignore-errors (delete-file f)))))))

;; run-playwright-s1-s6-preflight returns verdict struct
(define-test (playwright-artifact-canonicalizer-suite preflight-verdict-struct)
  (let* ((d (format nil "/tmp/orrery-pf-~D/" (get-universal-time)))
         (verdict (progn
                    (ensure-directories-exist (merge-pathnames "dummy" d))
                    (orrery/adapter:run-playwright-s1-s6-preflight
                     d orrery/adapter:*playwright-canonical-command*))))
    (unwind-protect
         (progn
           (true (orrery/adapter:playwright-preflight-verdict-p verdict))
           (true (orrery/adapter:ppv-command-ok-p verdict)))
      (when (probe-file d)
        (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
          (ignore-errors (delete-file f)))))))

;; canonicalization-report->json emits expected fields
(define-test (playwright-artifact-canonicalizer-suite report-json-fields)
  (let* ((d (format nil "/tmp/orrery-rj-~D/" (get-universal-time)))
         (report (progn
                   (ensure-directories-exist (merge-pathnames "dummy" d))
                   (orrery/adapter:build-playwright-canonicalization-report d)))
         (json (orrery/adapter:playwright-canonicalization-report->json report)))
    (unwind-protect
         (progn
           (true (search "\"pass\":" json))
           (true (search "\"missing\":" json))
           (true (search "\"records\":" json)))
      (when (probe-file d)
        (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
          (ignore-errors (delete-file f)))))))

;; preflight verdict->json emits expected fields
(define-test (playwright-artifact-canonicalizer-suite verdict-json-fields)
  (let* ((d (format nil "/tmp/orrery-vj-~D/" (get-universal-time)))
         (verdict (progn
                    (ensure-directories-exist (merge-pathnames "dummy" d))
                    (orrery/adapter:run-playwright-s1-s6-preflight
                     d orrery/adapter:*playwright-canonical-command*)))
         (json (orrery/adapter:playwright-preflight-verdict->json verdict)))
    (unwind-protect
         (progn
           (true (search "\"pass\":" json))
           (true (search "\"command_ok\":" json))
           (true (search "\"canonical_pass\":" json))
           (true (search "\"missing\":" json)))
      (when (probe-file d)
        (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
          (ignore-errors (delete-file f)))))))

;; Wrong command => command_ok=false
(define-test (playwright-artifact-canonicalizer-suite wrong-command-fails)
  (let* ((d (format nil "/tmp/orrery-wc-~D/" (get-universal-time)))
         (verdict (progn
                    (ensure-directories-exist (merge-pathnames "dummy" d))
                    (orrery/adapter:run-playwright-s1-s6-preflight
                     d "wrong-command"))))
    (unwind-protect
         (false (orrery/adapter:ppv-command-ok-p verdict))
      (when (probe-file d)
        (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
          (ignore-errors (delete-file f)))))))
