;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-packager-tests.lisp — Tests for S1-S6 evidence packager + replay index
;;; Bead: agent-orrery-7r2

(in-package #:orrery/harness-tests)

(define-test playwright-evidence-packager-suite)

(defun %mk-pkg-dir (prefix)
  (let ((d (format nil "/tmp/orrery-pkg-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %cleanup-pkg (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

;; Empty dir => 6 missing => ready=false
(define-test (playwright-evidence-packager-suite empty-dir-not-ready)
  (let* ((d (%mk-pkg-dir "empty"))
         (b (orrery/adapter:compile-playwright-evidence-bundle
             d orrery/adapter:*playwright-canonical-command*)))
    (unwind-protect
         (progn
           (false (orrery/adapter:peb-ready-p b))
           (is = 6 (orrery/adapter:peb-missing-count b))
           (is = 0 (orrery/adapter:peb-complete-count b))
           (is = 6 (length (orrery/adapter:peb-entries b))))
      (%cleanup-pkg d))))

;; JSON fields present
(define-test (playwright-evidence-packager-suite json-fields)
  (let* ((d (%mk-pkg-dir "json"))
         (b (orrery/adapter:compile-playwright-evidence-bundle
             d orrery/adapter:*playwright-canonical-command*))
         (json (orrery/adapter:playwright-evidence-bundle->json b)))
    (unwind-protect
         (progn
           (true (search "\"ready\":" json))
           (true (search "\"command_hash\":" json))
           (true (search "\"bundle_id\":" json))
           (true (search "\"complete_count\":" json))
           (true (search "\"replay_command\":" json))
           (true (search "\"entries\":" json)))
      (%cleanup-pkg d))))

;; Replay command contains canonical command
(define-test (playwright-evidence-packager-suite replay-command-contains-canonical)
  (let* ((d (%mk-pkg-dir "replay"))
         (b (orrery/adapter:compile-playwright-evidence-bundle
             d orrery/adapter:*playwright-canonical-command*))
         (entry (first (orrery/adapter:peb-entries b))))
    (unwind-protect
         (true (search orrery/adapter:*playwright-canonical-command*
                       (orrery/adapter:pbe-replay-command entry)))
      (%cleanup-pkg d))))

;; Command hash matches canonical
(define-test (playwright-evidence-packager-suite canonical-command-hash)
  (let* ((d (%mk-pkg-dir "hash"))
         (b (orrery/adapter:compile-playwright-evidence-bundle
             d orrery/adapter:*playwright-canonical-command*)))
    (unwind-protect
         (is = orrery/adapter:*playwright-canonical-command-hash*
             (orrery/adapter:peb-command-hash b))
      (%cleanup-pkg d))))

;; Ready with full evidence dir
(define-test (playwright-evidence-packager-suite full-evidence-ready)
  (let* ((d (%mk-pkg-dir "full"))
         (b (orrery/adapter:compile-playwright-evidence-bundle
             "test-results/e2e-regression-matrix/complete/"
             orrery/adapter:*playwright-canonical-command*)))
    (unwind-protect
         (progn
           (true (orrery/adapter:peb-ready-p b))
           (is = 6 (orrery/adapter:peb-complete-count b)))
      (%cleanup-pkg d))))
