;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-evidence-validator-tests.lisp — Tests for T1-T6 evidence validator + closure verdict
;;; Bead: agent-orrery-1ts

(in-package #:orrery/harness-tests)

(define-test t1-t6-evidence-validator-suite)

(defun %mk-1ts-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-1ts-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-1ts-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %cleanup-1ts-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %seed-full-t1t6-artifacts (dir)
  "Write all required artifacts for T1-T6 into DIR."
  (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
    (%touch-1ts-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%touch-1ts-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%touch-1ts-file (merge-pathnames (format nil "~A.cast" sid) dir) "cast")
    (%touch-1ts-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

;; --- closure verdict: pass path ---

(define-test (t1-t6-evidence-validator-suite verdict-pass-all-t1t6)
  (let ((dir (%mk-1ts-dir "pass")))
    (unwind-protect
         (progn
           (%seed-full-t1t6-artifacts dir)
           (let* ((v (orrery/adapter:evaluate-t1t6-evidence-validator
                      dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:t1t6-closure-verdict->json v)))
             (true (orrery/adapter:t1t6cv-pass-p v)
                   "verdict pass with complete T1-T6 artifacts")
             (true (orrery/adapter:t1t6cv-command-ok-p v)
                   "command ok with deterministic command")
             (is = 6 (length (orrery/adapter:t1t6cv-scenarios-passed v))
                 "6 scenarios passed")
             (is = 0 (length (orrery/adapter:t1t6cv-scenario-failures v))
                 "no scenario failures")
             (is = 0 (length (orrery/adapter:t1t6cv-missing-scenarios v))
                 "no missing scenarios")
             (is = 0 (length (orrery/adapter:t1t6cv-failure-diagnostics v))
                 "no failure diagnostics")
             (true (search "\"pass\":true" json) "JSON pass=true")
             (true (search "\"command_ok\":true" json) "JSON command_ok=true")
             (true (search "\"T6\"" json) "JSON contains T6")
             (true (search "\"failure_diagnostics\":[]" json) "no diagnostics in JSON")))
      (%cleanup-1ts-dir dir))))

;; --- closure verdict: fail on missing artifacts ---

(define-test (t1-t6-evidence-validator-suite verdict-fail-missing-cast-report)
  (let ((dir (%mk-1ts-dir "fail-partial")))
    (unwind-protect
         (progn
           ;; only screenshot + transcript; no cast, no report
           (dolist (sid '("T1" "T2" "T3" "T4" "T5" "T6"))
             (%touch-1ts-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
             (%touch-1ts-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt"))
           (let* ((v (orrery/adapter:evaluate-t1t6-evidence-validator
                      dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:t1t6-closure-verdict->json v)))
             (false (orrery/adapter:t1t6cv-pass-p v)
                    "verdict fails with incomplete artifacts")
             (is = 6 (length (orrery/adapter:t1t6cv-scenario-failures v))
                 "all 6 scenarios fail")
             (is = 6 (length (orrery/adapter:t1t6cv-failure-diagnostics v))
                 "6 failure diagnostics")
             (let ((f1 (first (orrery/adapter:t1t6cv-failure-diagnostics v))))
               (true (member :asciicast (orrery/adapter:t1t6sf-missing-artifacts f1))
                     "failure diagnostic notes missing asciicast")
               (true (member :machine-report (orrery/adapter:t1t6sf-missing-artifacts f1))
                     "failure diagnostic notes missing report"))
             (true (search "\"pass\":false" json) "JSON pass=false")
             (true (search "\"reason_code\"" json) "JSON includes reason_code")
             (true (search "\"missing-asciicast\"" json) "JSON includes missing-asciicast reason")))
      (%cleanup-1ts-dir dir))))

;; --- closure verdict: fail on wrong command ---

(define-test (t1-t6-evidence-validator-suite verdict-fail-wrong-command)
  (let ((dir (%mk-1ts-dir "fail-cmd")))
    (unwind-protect
         (progn
           (%seed-full-t1t6-artifacts dir)
           (let* ((v (orrery/adapter:evaluate-t1t6-evidence-validator
                      dir "make wrong-target"))
                  (json (orrery/adapter:t1t6-closure-verdict->json v)))
             (false (orrery/adapter:t1t6cv-pass-p v)
                    "verdict fails with wrong command")
             (false (orrery/adapter:t1t6cv-command-ok-p v)
                    "command_ok=false on wrong command")
             (true (search "\"command_ok\":false" json) "JSON command_ok=false")))
      (%cleanup-1ts-dir dir))))

;; --- closure verdict: fail on empty directory ---

(define-test (t1-t6-evidence-validator-suite verdict-fail-empty-dir)
  (let ((dir (%mk-1ts-dir "empty")))
    (unwind-protect
         (progn
           (let* ((v (orrery/adapter:evaluate-t1t6-evidence-validator
                      dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:t1t6-closure-verdict->json v)))
             (false (orrery/adapter:t1t6cv-pass-p v)
                    "verdict fails with empty directory")
             (is = 6 (length (orrery/adapter:t1t6cv-missing-scenarios v))
                 "all 6 scenarios missing")
             (true (search "\"pass\":false" json))))
      (%cleanup-1ts-dir dir))))

;; --- JSON serialisation ---

(define-test (t1-t6-evidence-validator-suite json-structure)
  (let ((dir (%mk-1ts-dir "json")))
    (unwind-protect
         (progn
           (%seed-full-t1t6-artifacts dir)
           (let ((json (orrery/adapter:t1t6-closure-verdict->json
                        (orrery/adapter:evaluate-t1t6-evidence-validator
                         dir "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))))
             (true (search "\"scenarios_required\"" json))
             (true (search "\"scenarios_passed\"" json))
             (true (search "\"scenario_failures\"" json))
             (true (search "\"missing_scenarios\"" json))
             (true (search "\"failure_diagnostics\"" json))
             (true (search "\"command_hash\"" json))
             (true (search "\"deterministic_command\"" json))
             (true (search "\"timestamp\"" json))
             (true (search "\"detail\"" json))))
      (%cleanup-1ts-dir dir))))

;; --- scorecard->t1t6 conversion (unit) ---

(define-test (t1-t6-evidence-validator-suite scorecard-to-verdict-unit)
  (let* ((score (orrery/adapter:make-mcp-tui-scenario-score
                 :scenario-id "T1"
                 :screenshot-p t
                 :transcript-p t
                 :asciicast-p nil
                 :report-p nil
                 :score 2
                 :pass-p nil))
         (scorecard (orrery/adapter:make-mcp-tui-scorecard-result
                     :pass-p nil
                     :command-match-p t
                     :command-hash 42
                     :scenario-scores (list score)
                     :missing-scenarios nil
                     :detail "test"
                     :timestamp 0))
         (v (orrery/adapter:scorecard->t1t6-closure-verdict scorecard)))
    (false (orrery/adapter:t1t6cv-pass-p v))
    (true  (orrery/adapter:t1t6cv-command-ok-p v))
    (is = 42 (orrery/adapter:t1t6cv-command-hash v))
    (is = 1 (length (orrery/adapter:t1t6cv-failure-diagnostics v)))
    (let ((f (first (orrery/adapter:t1t6cv-failure-diagnostics v))))
      (is string= "T1" (orrery/adapter:t1t6sf-scenario-id f))
      (true (member :asciicast (orrery/adapter:t1t6sf-missing-artifacts f)))
      (true (member :machine-report (orrery/adapter:t1t6sf-missing-artifacts f))))))
