;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cross-framework-evidence-harmonizer-tests.lisp — Tests for cross-framework harmonizer
;;; Bead: agent-orrery-uzma

(in-package #:orrery/harness-tests)

(define-test cross-framework-evidence-harmonizer-suite)

(defun %make-empty-tui-bundle ()
  (let* ((d (format nil "/tmp/orrery-uz-tui-~D/" (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    (prog1 (orrery/adapter:notarize-tui-evidence-bundle
            d orrery/adapter:*mcp-tui-deterministic-command*)
      (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
        (ignore-errors (delete-file f))))))

(defun %make-empty-pw-bundle ()
  (let ((d (format nil "/tmp/orrery-uz-pw-~D/" (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    (prog1 (orrery/adapter:compile-playwright-evidence-bundle
            d orrery/adapter:*playwright-canonical-command*)
      (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
        (ignore-errors (delete-file f))))))

;; harmonize-tui-evidence: 6 rows
(define-test (cross-framework-evidence-harmonizer-suite tui-six-rows)
  (let* ((bundle (%make-empty-tui-bundle))
         (rows (orrery/adapter:harmonize-tui-evidence bundle)))
    (is = 6 (length rows))
    (true (every (lambda (r) (eq :mcp-tui (orrery/adapter:hsr-framework r))) rows))))

;; harmonize-playwright-evidence: 6 rows
(define-test (cross-framework-evidence-harmonizer-suite pw-six-rows)
  (let* ((bundle (%make-empty-pw-bundle))
         (rows (orrery/adapter:harmonize-playwright-evidence bundle)))
    (is = 6 (length rows))
    (true (every (lambda (r) (eq :playwright (orrery/adapter:hsr-framework r))) rows))))

;; compile-harmonized-envelope: overall-pass=false on empty
(define-test (cross-framework-evidence-harmonizer-suite empty-envelope-fails)
  (let* ((tui (%make-empty-tui-bundle))
         (pw  (%make-empty-pw-bundle))
         (env (orrery/adapter:compile-harmonized-envelope tui pw)))
    (false (orrery/adapter:hee-overall-pass-p env))
    (is = 12 (+ (length (orrery/adapter:hee-epic3-rows env))
                (length (orrery/adapter:hee-epic4-rows env))))))

;; JSON fields
(define-test (cross-framework-evidence-harmonizer-suite json-fields)
  (let* ((tui (%make-empty-tui-bundle))
         (pw  (%make-empty-pw-bundle))
         (env (orrery/adapter:compile-harmonized-envelope tui pw))
         (json (orrery/adapter:harmonized-evidence-envelope->json env)))
    (true (search "\"envelope_id\":" json))
    (true (search "\"epic3_pass\":" json))
    (true (search "\"epic4_pass\":" json))
    (true (search "\"overall_pass\":" json))
    (true (search "\"epic3_rows\":" json))
    (true (search "\"epic4_rows\":" json))))

;; Struct accessors
(define-test (cross-framework-evidence-harmonizer-suite struct-accessors)
  (let ((row (orrery/adapter::make-harmonized-scenario-row
              :scenario-id "S1" :framework :playwright
              :command "cmd" :command-hash 42
              :evidence-ok-p t :artifact-count 2
              :digest-key "dk" :detail "ok")))
    (is string= "S1" (orrery/adapter:hsr-scenario-id row))
    (is eq :playwright (orrery/adapter:hsr-framework row))
    (true (orrery/adapter:hsr-evidence-ok-p row))))
