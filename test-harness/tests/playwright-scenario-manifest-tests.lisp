;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-scenario-manifest-tests.lisp — Tests for typed S1-S6 scenario manifest ADTs
;;; Bead: agent-orrery-2w69

(in-package #:orrery/harness-tests)

(define-test playwright-scenario-manifest-suite)

(defun %mk-psm-dir (prefix)
  (let ((d (format nil "/tmp/orrery-psm-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %touch-psm (p c)
  (with-open-file (s p :direction :output :if-exists :supersede)
    (write-string c s)))

(defun %cleanup-psm (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

;; Struct field accessors work
(define-test (playwright-scenario-manifest-suite struct-accessors)
  (let ((entry (orrery/adapter::make-playwright-scenario-manifest-entry
                :scenario-id "S1"
                :command "cd e2e && ./run-e2e.sh"
                :command-hash 42
                :screenshot nil
                :trace nil
                :complete-p nil
                :detail "S1: missing screenshot,trace")))
    (is string= "S1" (orrery/adapter:psme-scenario-id entry))
    (false (orrery/adapter:psme-complete-p entry))
    (is = 42 (orrery/adapter:psme-command-hash entry))))

;; Empty dir => all missing => pass=false
(define-test (playwright-scenario-manifest-suite empty-dir-all-missing)
  (let* ((d (%mk-psm-dir "empty"))
         (manifest (orrery/adapter:compile-playwright-scenario-manifest d "cd e2e && ./run-e2e.sh")))
    (unwind-protect
         (progn
           (false (orrery/adapter:psm-pass-p manifest))
           (is = 6 (orrery/adapter:psm-total-count manifest))
           (is = 0 (orrery/adapter:psm-complete-count manifest))
           (is = 6 (orrery/adapter:psm-missing-count manifest))
           (is = 6 (length (orrery/adapter:psm-entries manifest))))
      (%cleanup-psm d))))

;; JSON emits expected fields
(define-test (playwright-scenario-manifest-suite json-fields)
  (let* ((d (%mk-psm-dir "json"))
         (manifest (orrery/adapter:compile-playwright-scenario-manifest d "cd e2e && ./run-e2e.sh"))
         (json (orrery/adapter:playwright-scenario-manifest->json manifest)))
    (unwind-protect
         (progn
           (true (search "\"pass\":" json))
           (true (search "\"command_hash\":" json))
           (true (search "\"total\":" json))
           (true (search "\"complete\":" json))
           (true (search "\"missing\":" json))
           (true (search "\"entries\":" json))
           (true (search "\"scenario\":\"S1\"" json)))
      (%cleanup-psm d))))

;; command-hash matches canonical
(define-test (playwright-scenario-manifest-suite canonical-command-hash)
  (let* ((d (%mk-psm-dir "hash"))
         (manifest (orrery/adapter:compile-playwright-scenario-manifest
                    d orrery/adapter:*playwright-canonical-command*)))
    (unwind-protect
         (is = orrery/adapter:*playwright-canonical-command-hash*
             (orrery/adapter:psm-command-hash manifest))
      (%cleanup-psm d))))

;; Artifact descriptor struct
(define-test (playwright-scenario-manifest-suite artifact-descriptor-struct)
  (let ((d (orrery/adapter::make-playwright-artifact-descriptor
            :scenario-id "S3"
            :kind :trace
            :path "/tmp/trace.zip"
            :present-p nil
            :digest "")))
    (is string= "S3" (orrery/adapter:pad-scenario-id d))
    (is eq :trace (orrery/adapter:pad-kind d))
    (false (orrery/adapter:pad-present-p d))))
