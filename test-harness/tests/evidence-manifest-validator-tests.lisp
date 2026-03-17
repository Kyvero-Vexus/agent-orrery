;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; e2e-manifest-validator-tests.lisp — Tests for evidence manifest validator
;;;
;;; Beads: agent-orrery-qo5, agent-orrery-oo1

(in-package #:orrery/harness-tests)

;;; ============================================================
;;; Evidence Manifest Validator Tests
;;; ============================================================

(define-test e2e-manifest-tests)

;;; --- Policy constants ---

(define-test (e2e-manifest-tests web-required-scenarios)
  "Web policy requires exactly S1-S6."
  (is = 6 (length orrery/adapter::*web-required-scenarios*))
  (dolist (s '("S1" "S2" "S3" "S4" "S5" "S6"))
    (true (member s orrery/adapter::*web-required-scenarios* :test #'string=))))

(define-test (e2e-manifest-tests tui-required-scenarios)
  "TUI policy requires exactly T1-T8."
  (is = 8 (length orrery/adapter::*tui-required-scenarios*))
  (dolist (s '("T1" "T2" "T3" "T4" "T5" "T6" "T7" "T8"))
    (true (member s orrery/adapter::*tui-required-scenarios* :test #'string=))))

(define-test (e2e-manifest-tests web-deterministic-command)
  "Web deterministic command is set."
  (true (plusp (length orrery/adapter::*web-deterministic-command*)))
  (true (search "run-e2e" orrery/adapter::*web-deterministic-command*)))

(define-test (e2e-manifest-tests tui-deterministic-command)
  "TUI deterministic command is set."
  (true (plusp (length orrery/adapter::*tui-deterministic-command*)))
  (true (search "e2e-tui" orrery/adapter::*tui-deterministic-command*)))

;;; --- Struct construction ---

(define-test (e2e-manifest-tests artifact-construction)
  "manifest-artifact struct can be constructed and accessed."
  (let ((art (orrery/adapter:make-manifest-artifact
              :scenario-id "S1"
              :kind :screenshot
              :path "/tmp/s1-screenshot.png"
              :exists-p t
              :size-bytes 12345)))
    (is string= "S1" (orrery/adapter:manifest-artifact-scenario-id art))
    (is eq :screenshot (orrery/adapter:manifest-artifact-kind art))
    (is string= "/tmp/s1-screenshot.png" (orrery/adapter:manifest-artifact-path art))
    (true (orrery/adapter:manifest-artifact-exists-p art))
    (is = 12345 (orrery/adapter:manifest-artifact-size-bytes art))))

(define-test (e2e-manifest-tests manifest-construction)
  "e2e-manifest struct can be constructed."
  (let ((m (orrery/adapter:make-e2e-manifest
            :suite :web-playwright
            :artifacts nil
            :scenarios-required '("S1")
            :deterministic-command "test"
            :valid-p nil
            :missing '("S1: missing :screenshot artifact")
            :errors nil)))
    (is eq :web-playwright (orrery/adapter:e2e-manifest-suite m))
    (false (orrery/adapter:e2e-manifest-valid-p m))
    (is = 1 (length (orrery/adapter:e2e-manifest-missing m)))))

;;; --- Validation with empty directory ---

(define-test (e2e-manifest-tests empty-dir-fails-web)
  "Validating against nonexistent dir → all scenarios missing."
  (let ((m (orrery/adapter:validate-e2e-manifest
            :web-playwright "/tmp/nonexistent-evidence-dir-xyz/")))
    (false (orrery/adapter:e2e-manifest-valid-p m))
    ;; Should have 12 missing entries (6 scenarios × 2 required kinds)
    (is = 12 (length (orrery/adapter:e2e-manifest-missing m)))))

(define-test (e2e-manifest-tests empty-dir-fails-tui)
  "Validating against nonexistent dir → all TUI scenarios missing."
  (let ((m (orrery/adapter:validate-e2e-manifest
            :tui-mcp-driver "/tmp/nonexistent-evidence-dir-xyz/")))
    (false (orrery/adapter:e2e-manifest-valid-p m))
    ;; Should have 16 missing entries (8 scenarios × 2 required kinds)
    (is = 18 (length (orrery/adapter:e2e-manifest-missing m)))))

;;; --- Validation with populated temp directory ---

(defun %create-temp-evidence-dir (prefix scenarios artifact-specs)
  "Create a temp directory with fake evidence files.
ARTIFACT-SPECS is list of (scenario-suffix . extension) pairs."
  (let ((dir (format nil "/tmp/orrery-evidence-test-~A-~D/"
                     prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    (dolist (scenario scenarios)
      (dolist (spec artifact-specs)
        (let* ((suffix (car spec))
               (ext (cdr spec))
               (filename (format nil "~A-~A.~A"
                                 (string-downcase scenario) suffix ext))
               (filepath (merge-pathnames filename dir)))
          (with-open-file (s filepath :direction :output :if-exists :supersede)
            (write-string "test content" s)))))
    dir))

(defun %cleanup-temp-dir (dir)
  "Remove temp evidence directory."
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames
                           (make-pathname :name :wild :type :wild)
                           (pathname dir))))
      (delete-file f))
    (ignore-errors (delete-file (pathname dir)))))

(define-test (e2e-manifest-tests valid-web-evidence)
  "Complete web evidence set → valid manifest."
  (let ((dir (%create-temp-evidence-dir
              "web"
              '("S1" "S2" "S3" "S4" "S5" "S6")
              '(("screenshot" . "png") ("trace" . "zip")))))
    (unwind-protect
         (let ((m (orrery/adapter:validate-e2e-manifest :web-playwright dir)))
           (true (orrery/adapter:e2e-manifest-valid-p m))
           (is = 0 (length (orrery/adapter:e2e-manifest-missing m)))
           (is = 0 (length (orrery/adapter:e2e-manifest-errors m)))
           (is = 12 (length (orrery/adapter:e2e-manifest-artifacts m))))
      (%cleanup-temp-dir dir))))

(define-test (e2e-manifest-tests valid-tui-evidence)
  "Complete TUI evidence set → valid manifest."
  (let ((dir (%create-temp-evidence-dir
              "tui"
              '("T1" "T2" "T3" "T4" "T5" "T6" "T7" "T8")
              '(("screenshot" . "png") ("transcript" . "txt")))))
    ;; Suite-level artifacts required for TUI
    (with-open-file (s (merge-pathnames "tui-e2e-report.json" dir)
                       :direction :output :if-exists :supersede)
      (write-string "report" s))
    (with-open-file (s (merge-pathnames "tui-e2e-session.cast" dir)
                       :direction :output :if-exists :supersede)
      (write-string "cast" s))
    (unwind-protect
         (let ((m (orrery/adapter:validate-e2e-manifest :tui-mcp-driver dir)))
           (true (orrery/adapter:e2e-manifest-valid-p m))
           (is = 0 (length (orrery/adapter:e2e-manifest-missing m)))
           (is = 0 (length (orrery/adapter:e2e-manifest-errors m))))
      (%cleanup-temp-dir dir))))

(define-test (e2e-manifest-tests tui-missing-suite-artifacts-fails)
  "TUI manifest without suite-level report/cast should fail."
  (let ((dir (%create-temp-evidence-dir
              "tui-nosuite"
              '("T1" "T2" "T3" "T4" "T5" "T6" "T7" "T8")
              '(("screenshot" . "png") ("transcript" . "txt")))))
    (unwind-protect
         (let ((m (orrery/adapter:validate-e2e-manifest :tui-mcp-driver dir)))
           (false (orrery/adapter:e2e-manifest-valid-p m))
           (true (find "SUITE: missing REPORT artifact" (orrery/adapter:e2e-manifest-missing m)
                       :test #'string=))
           (true (find "SUITE: missing ASCIICAST artifact" (orrery/adapter:e2e-manifest-missing m)
                       :test #'string=)))
      (%cleanup-temp-dir dir))))

(define-test (e2e-manifest-tests partial-web-evidence)
  "Missing S3 screenshot → invalid manifest."
  (let ((dir (%create-temp-evidence-dir
              "web-partial"
              '("S1" "S2" "S4" "S5" "S6")
              '(("screenshot" . "png") ("trace" . "zip")))))
    ;; Add S3 trace but no screenshot
    (with-open-file (s (merge-pathnames "s3-trace.zip" dir)
                       :direction :output :if-exists :supersede)
      (write-string "trace" s))
    (unwind-protect
         (let ((m (orrery/adapter:validate-e2e-manifest :web-playwright dir)))
           (false (orrery/adapter:e2e-manifest-valid-p m))
           (true (find "S3" (orrery/adapter:e2e-manifest-missing m)
                       :test (lambda (s item) (search s item)))))
      (%cleanup-temp-dir dir))))

;;; --- Report output ---

(define-test (e2e-manifest-tests report-pass)
  "Valid manifest report contains PASS."
  (let ((dir (%create-temp-evidence-dir
              "report-pass"
              '("S1" "S2" "S3" "S4" "S5" "S6")
              '(("screenshot" . "png") ("trace" . "zip")))))
    (unwind-protect
         (let* ((m (orrery/adapter:validate-e2e-manifest :web-playwright dir))
                (output (with-output-to-string (s)
                          (orrery/adapter:report-manifest-validity m s))))
           (true (search "PASS" output)))
      (%cleanup-temp-dir dir))))

(define-test (e2e-manifest-tests report-fail)
  "Invalid manifest report contains FAIL."
  (let ((m (orrery/adapter:validate-e2e-manifest
            :web-playwright "/tmp/nonexistent-xyz/")))
    (let ((output (with-output-to-string (s)
                    (orrery/adapter:report-manifest-validity m s))))
      (true (search "FAIL" output))
      (true (search "Missing" output)))))

;;; --- Type safety checks ---

(define-test (e2e-manifest-tests evidence-kind-type)
  "evidence-kind type check."
  (true (typep :screenshot 'orrery/adapter::evidence-kind))
  (true (typep :trace 'orrery/adapter::evidence-kind))
  (true (typep :report 'orrery/adapter::evidence-kind))
  (true (typep :transcript 'orrery/adapter::evidence-kind))
  (true (typep :asciicast 'orrery/adapter::evidence-kind))
  (false (typep :invalid 'orrery/adapter::evidence-kind)))

(define-test (e2e-manifest-tests normalize-artifact-path)
  "Artifact path normalization is deterministic."
  (is string= "s1-trace.zip"
      (orrery/adapter:normalize-artifact-path "/tmp/ABC/S1-TRACE.ZIP"))
  (is string= "t3-screenshot.png"
      (orrery/adapter:normalize-artifact-path "T3-SCREENSHOT.PNG")))

(define-test (e2e-manifest-tests normalize-manifest-artifacts-dedup-and-sort)
  "Normalizer deduplicates by (scenario,kind) and keeps largest artifact."
  (let* ((artifacts (list
                     (orrery/adapter:make-manifest-artifact
                      :scenario-id "s2" :kind :trace :path "/tmp/S2-trace.zip" :exists-p t :size-bytes 10)
                     (orrery/adapter:make-manifest-artifact
                      :scenario-id "S1" :kind :screenshot :path "S1-shot.png" :exists-p t :size-bytes 30)
                     (orrery/adapter:make-manifest-artifact
                      :scenario-id "S2" :kind :trace :path "S2-trace-better.zip" :exists-p t :size-bytes 20)))
         (normalized (orrery/adapter:normalize-manifest-artifacts artifacts)))
    (is = 2 (length normalized))
    ;; Sorted by scenario then kind; S1 screenshot first.
    (is string= "S1" (orrery/adapter:manifest-artifact-scenario-id (first normalized)))
    ;; S2 trace should be the larger one (20 bytes) after dedup.
    (is = 20 (orrery/adapter:manifest-artifact-size-bytes (second normalized)))))

(define-test (e2e-manifest-tests validate-and-normalize)
  "Validation+normalization returns sorted scenarios and deterministic artifacts."
  (let ((dir (%create-temp-evidence-dir
              "normalize"
              '("S1" "S2" "S3" "S4" "S5" "S6")
              '(("screenshot" . "png") ("trace" . "zip")))))
    (unwind-protect
         (let ((m (orrery/adapter:validate-and-normalize-e2e-manifest
                   :web-playwright dir)))
           (true (orrery/adapter:e2e-manifest-valid-p m))
           (is = 12 (length (orrery/adapter:e2e-manifest-artifacts m)))
           (is string= "S1" (first (orrery/adapter:e2e-manifest-scenarios-required m))))
      (%cleanup-temp-dir dir))))

(define-test (e2e-manifest-tests epic3-guard-pass)
  "Epic 3 guard passes with T1-T6 + suite artifacts present."
  (let ((dir (%create-temp-evidence-dir
              "epic3-guard-pass"
              '("T1" "T2" "T3" "T4" "T5" "T6" "T7" "T8")
              '(("screenshot" . "png") ("transcript" . "txt")))))
    (with-open-file (s (merge-pathnames "tui-e2e-report.json" dir)
                       :direction :output :if-exists :supersede)
      (write-string "report" s))
    (with-open-file (s (merge-pathnames "tui-e2e-session.cast" dir)
                       :direction :output :if-exists :supersede)
      (write-string "cast" s))
    (unwind-protect
         (true (orrery/adapter:epic3-t1-t6-evidence-ok-p dir))
      (%cleanup-temp-dir dir))))

(define-test (e2e-manifest-tests epic3-guard-fail-missing-t6)
  "Epic 3 guard fails when T6 artifacts are missing."
  (let ((dir (%create-temp-evidence-dir
              "epic3-guard-fail"
              '("T1" "T2" "T3" "T4" "T5" "T7" "T8")
              '(("screenshot" . "png") ("transcript" . "txt")))))
    (with-open-file (s (merge-pathnames "tui-e2e-report.json" dir)
                       :direction :output :if-exists :supersede)
      (write-string "report" s))
    (with-open-file (s (merge-pathnames "tui-e2e-session.cast" dir)
                       :direction :output :if-exists :supersede)
      (write-string "cast" s))
    (unwind-protect
         (false (orrery/adapter:epic3-t1-t6-evidence-ok-p dir))
      (%cleanup-temp-dir dir))))

(define-test (e2e-manifest-tests evidence-suite-type)
  "evidence-suite type check."
  (true (typep :web-playwright 'orrery/adapter::evidence-suite))
  (true (typep :tui-mcp-driver 'orrery/adapter::evidence-suite))
  (false (typep :invalid 'orrery/adapter::evidence-suite)))
