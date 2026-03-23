;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-replay-certificate-tests.lisp — Tests for Playwright replay-certificate compiler
;;; Bead: agent-orrery-0vdb

(in-package #:orrery/harness-tests)

(define-test playwright-replay-certificate-suite)

(defun %mk-replay-cert-dir (prefix)
  (let ((d (format nil "/tmp/orrery-replay-cert-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %touch-replay-cert (p c)
  (with-open-file (s p :direction :output :if-exists :supersede)
    (write-string c s)))

(defun %cleanup-replay-cert (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames
                           (make-pathname :name :wild :type :wild)
                           (pathname d))))
      (ignore-errors (delete-file f)))))

;;; --- compile-playwright-replay-certificate ---

(define-test (playwright-replay-certificate-suite compile-complete-cert)
  "Full S1-S6 manifest → closure-ready certificate."
  (let ((d (%mk-replay-cert-dir "complete")))
    (unwind-protect
         (progn
           (%touch-replay-cert (merge-pathnames "playwright-report.json" d) "ok")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-replay-cert (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-replay-cert (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let* ((manifest (orrery/adapter:compile-playwright-evidence-manifest d "cd e2e && ./run-e2e.sh"))
                  (cert (orrery/adapter:compile-playwright-replay-certificate manifest "cd e2e && ./run-e2e.sh")))
             (true (orrery/adapter:playwright-replay-certificate-p cert))
             (true (orrery/adapter:prc-command-canonical-p cert))
             (true (orrery/adapter:prc-closure-ready-p cert))
             (is = 6 (orrery/adapter:prc-scenario-count cert))
             (is = 6 (orrery/adapter:prc-complete-scenario-count cert))
             (is = 0 (length (orrery/adapter:prc-missing-scenarios cert)))
             (is = 6 (length (orrery/adapter:prc-rows cert)))
             (true (plusp (length (orrery/adapter:prc-ledger-hash cert))))))
      (%cleanup-replay-cert d))))

(define-test (playwright-replay-certificate-suite compile-incomplete-cert)
  "Missing S3 screenshots → not closure-ready, S3 in missing list."
  (let ((d (%mk-replay-cert-dir "incomplete")))
    (unwind-protect
         (progn
           (%touch-replay-cert (merge-pathnames "playwright-report.json" d) "ok")
           (dolist (sid '("S1" "S2" "S4" "S5" "S6"))
             (%touch-replay-cert (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-replay-cert (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let* ((manifest (orrery/adapter:compile-playwright-evidence-manifest d "cd e2e && ./run-e2e.sh"))
                  (cert (orrery/adapter:compile-playwright-replay-certificate manifest "cd e2e && ./run-e2e.sh")))
             (false (orrery/adapter:prc-closure-ready-p cert))
             (true (member "S3" (orrery/adapter:prc-missing-scenarios cert) :test #'string=))))
      (%cleanup-replay-cert d))))

(define-test (playwright-replay-certificate-suite compile-non-canonical-command)
  "Non-canonical command → command-canonical-p NIL, not closure-ready."
  (let ((d (%mk-replay-cert-dir "badcmd")))
    (unwind-protect
         (progn
           (%touch-replay-cert (merge-pathnames "playwright-report.json" d) "ok")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-replay-cert (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-replay-cert (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let* ((manifest (orrery/adapter:compile-playwright-evidence-manifest d "npx playwright test"))
                  (cert (orrery/adapter:compile-playwright-replay-certificate manifest "npx playwright test")))
             (false (orrery/adapter:prc-command-canonical-p cert))
             (false (orrery/adapter:prc-closure-ready-p cert))))
      (%cleanup-replay-cert d))))

;;; --- export-playwright-artifact-ledger ---

(define-test (playwright-replay-certificate-suite export-ledger-pass)
  "Complete cert → passing ledger with 6 entries."
  (let ((d (%mk-replay-cert-dir "ledger-pass")))
    (unwind-protect
         (progn
           (%touch-replay-cert (merge-pathnames "playwright-report.json" d) "ok")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-replay-cert (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-replay-cert (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let* ((manifest (orrery/adapter:compile-playwright-evidence-manifest d "cd e2e && ./run-e2e.sh"))
                  (cert (orrery/adapter:compile-playwright-replay-certificate manifest "cd e2e && ./run-e2e.sh"))
                  (ledger (orrery/adapter:export-playwright-artifact-ledger cert)))
             (true (orrery/adapter:playwright-artifact-ledger-p ledger))
             (true (orrery/adapter:pal-pass-p ledger))
             (is = 6 (orrery/adapter:pal-scenario-count ledger))
             (is = 6 (orrery/adapter:pal-complete-count ledger))
             (is = 6 (length (orrery/adapter:pal-entries ledger)))
             (true (every #'orrery/adapter:pale-present-p (orrery/adapter:pal-entries ledger)))
             (true (plusp (length (orrery/adapter:pal-ledger-hash ledger))))))
      (%cleanup-replay-cert d))))

(define-test (playwright-replay-certificate-suite export-ledger-fail)
  "Incomplete cert → failing ledger."
  (let ((d (%mk-replay-cert-dir "ledger-fail")))
    (unwind-protect
         (progn
           (%touch-replay-cert (merge-pathnames "playwright-report.json" d) "ok")
           (dolist (sid '("S1" "S2"))
             (%touch-replay-cert (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-replay-cert (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let* ((manifest (orrery/adapter:compile-playwright-evidence-manifest d "cd e2e && ./run-e2e.sh"))
                  (cert (orrery/adapter:compile-playwright-replay-certificate manifest "cd e2e && ./run-e2e.sh"))
                  (ledger (orrery/adapter:export-playwright-artifact-ledger cert)))
             (false (orrery/adapter:pal-pass-p ledger))
             (is = 6 (orrery/adapter:pal-scenario-count ledger))
             (true (< (orrery/adapter:pal-complete-count ledger) 6))))
      (%cleanup-replay-cert d))))

;;; --- JSON serializers ---

(define-test (playwright-replay-certificate-suite cert-json-output)
  "JSON output contains expected keys."
  (let ((d (%mk-replay-cert-dir "json")))
    (unwind-protect
         (progn
           (%touch-replay-cert (merge-pathnames "playwright-report.json" d) "ok")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-replay-cert (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-replay-cert (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let* ((manifest (orrery/adapter:compile-playwright-evidence-manifest d "cd e2e && ./run-e2e.sh"))
                  (cert (orrery/adapter:compile-playwright-replay-certificate manifest "cd e2e && ./run-e2e.sh"))
                  (json (orrery/adapter:playwright-replay-certificate->json cert)))
             (true (search "run_id" json))
             (true (search "deterministic_command" json))
             (true (search "closure_ready" json))
             (true (search "ledger_hash" json))
             (true (search "rows" json))))
      (%cleanup-replay-cert d))))

(define-test (playwright-replay-certificate-suite ledger-json-output)
  "Ledger JSON output contains expected keys."
  (let ((d (%mk-replay-cert-dir "ledger-json")))
    (unwind-protect
         (progn
           (%touch-replay-cert (merge-pathnames "playwright-report.json" d) "ok")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-replay-cert (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-replay-cert (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let* ((manifest (orrery/adapter:compile-playwright-evidence-manifest d "cd e2e && ./run-e2e.sh"))
                  (cert (orrery/adapter:compile-playwright-replay-certificate manifest "cd e2e && ./run-e2e.sh"))
                  (ledger (orrery/adapter:export-playwright-artifact-ledger cert))
                  (json (orrery/adapter:playwright-artifact-ledger->json ledger)))
             (true (search "cert_run_id" json))
             (true (search "entries" json))
             (true (search "pass" json))
             (true (search "ledger_hash" json))))
      (%cleanup-replay-cert d))))

;;; --- Ledger hash determinism ---

(define-test (playwright-replay-certificate-suite ledger-hash-determinism)
  "Same rows produce same ledger hash."
  (let ((d (%mk-replay-cert-dir "hash-det")))
    (unwind-protect
         (progn
           (%touch-replay-cert (merge-pathnames "playwright-report.json" d) "ok")
           (dolist (sid '("S1" "S2" "S3" "S4" "S5" "S6"))
             (%touch-replay-cert (merge-pathnames (format nil "~A-screenshot.png" (string-downcase sid)) d) "png")
             (%touch-replay-cert (merge-pathnames (format nil "~A-trace.zip" (string-downcase sid)) d) "zip"))
           (let* ((manifest (orrery/adapter:compile-playwright-evidence-manifest d "cd e2e && ./run-e2e.sh"))
                  (cert1 (orrery/adapter:compile-playwright-replay-certificate manifest "cd e2e && ./run-e2e.sh"))
                  (cert2 (orrery/adapter:compile-playwright-replay-certificate manifest "cd e2e && ./run-e2e.sh")))
             (is string= (orrery/adapter:prc-ledger-hash cert1) (orrery/adapter:prc-ledger-hash cert2))))
      (%cleanup-replay-cert d))))
