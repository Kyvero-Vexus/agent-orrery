;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-attestation-merger-tests.lisp — tests for S1-S6 canonical attestation merger
;;; Bead: agent-orrery-k75i

(in-package #:orrery/harness-tests)

(define-test playwright-attestation-merger-suite)

;;; ── helpers ──────────────────────────────────────────────────────────────────

(defun %mk-full-attestation-ledger ()
  "Build a ledger with all 6 scenarios having canonical command hash and artifacts."
  (let* ((canonical-cmd orrery/adapter:*playwright-canonical-command*)
         (h (orrery/adapter:command-fingerprint canonical-cmd))
         (atts (mapcar (lambda (sid)
                         (orrery/adapter:make-web-scenario-attestation
                          :scenario-id sid
                          :command-fingerprint h
                          :screenshot-path (format nil "/e2e/~A/screenshot.png" sid)
                          :trace-path (format nil "/e2e/~A/trace.zip" sid)
                          :screenshot-hash "abc"
                          :trace-hash "def"
                          :attested-p t))
                       orrery/adapter:*playwright-required-scenarios*)))
    (orrery/adapter:make-playwright-scenario-ledger
     :run-id "merge-test-001"
     :command canonical-cmd
     :attestations atts
     :timestamp 0)))

(defun %mk-partial-attestation-ledger ()
  "Build a ledger missing S3."
  (let* ((canonical-cmd orrery/adapter:*playwright-canonical-command*)
         (h (orrery/adapter:command-fingerprint canonical-cmd))
         (scenarios (remove "S3" orrery/adapter:*playwright-required-scenarios* :test #'string=))
         (atts (mapcar (lambda (sid)
                         (orrery/adapter:make-web-scenario-attestation
                          :scenario-id sid
                          :command-fingerprint h
                          :screenshot-path (format nil "/e2e/~A/screenshot.png" sid)
                          :trace-path (format nil "/e2e/~A/trace.zip" sid)
                          :screenshot-hash "abc"
                          :trace-hash "def"
                          :attested-p t))
                       scenarios)))
    (orrery/adapter:make-playwright-scenario-ledger
     :run-id "merge-test-partial"
     :command canonical-cmd
     :attestations atts
     :timestamp 0)))

(defun %mk-drift-attestation-ledger ()
  "Build a ledger where S4 has a drifted command hash."
  (let* ((canonical-cmd orrery/adapter:*playwright-canonical-command*)
         (h-good (orrery/adapter:command-fingerprint canonical-cmd))
         (h-bad (orrery/adapter:command-fingerprint "cd e2e && ./old-run.sh"))
         (atts (loop for sid in orrery/adapter:*playwright-required-scenarios*
                     collect (orrery/adapter:make-web-scenario-attestation
                              :scenario-id sid
                              :command-fingerprint (if (string= sid "S4") h-bad h-good)
                              :screenshot-path (format nil "/e2e/~A/screenshot.png" sid)
                              :trace-path (format nil "/e2e/~A/trace.zip" sid)
                              :screenshot-hash "abc"
                              :trace-hash "def"
                              :attested-p t))))
    (orrery/adapter:make-playwright-scenario-ledger
     :run-id "merge-test-drift"
     :command canonical-cmd
     :attestations atts
     :timestamp 0)))

(defun %mk-missing-artifact-ledger ()
  "Build a ledger where S5 is missing trace."
  (let* ((canonical-cmd orrery/adapter:*playwright-canonical-command*)
         (h (orrery/adapter:command-fingerprint canonical-cmd))
         (atts (loop for sid in orrery/adapter:*playwright-required-scenarios*
                     collect (orrery/adapter:make-web-scenario-attestation
                              :scenario-id sid
                              :command-fingerprint h
                              :screenshot-path (format nil "/e2e/~A/screenshot.png" sid)
                              :trace-path (if (string= sid "S5") "" (format nil "/e2e/~A/trace.zip" sid))
                              :screenshot-hash "abc"
                              :trace-hash (if (string= sid "S5") "" "def")
                              :attested-p (not (string= sid "S5"))))))
    (orrery/adapter:make-playwright-scenario-ledger
     :run-id "merge-test-artifact"
     :command canonical-cmd
     :attestations atts
     :timestamp 0)))

;;; ── tests ────────────────────────────────────────────────────────────────────

(define-test (playwright-attestation-merger-suite pass-when-all-present)
  "All S1-S6 with canonical hash and artifacts => merger passes."
  (let* ((ledger (%mk-full-attestation-ledger))
         (report (orrery/adapter:merge-playwright-attestations->envelope ledger)))
    (true (orrery/adapter:pwam-pass-p report))
    (true (orrery/adapter:pwam-command-match-p report))
    (is = 6 (length (orrery/adapter:pwam-rows report)))
    (true (null (orrery/adapter:pwam-missing-scenarios report)))
    (true (null (orrery/adapter:pwam-drift-scenarios report)))))

(define-test (playwright-attestation-merger-suite fail-on-nil-ledger)
  "Nil ledger => all scenarios missing, report fails."
  (let ((report (orrery/adapter:merge-playwright-attestations->envelope nil)))
    (false (orrery/adapter:pwam-pass-p report))
    (false (orrery/adapter:pwam-command-match-p report))
    (is = 6 (length (orrery/adapter:pwam-missing-scenarios report)))
    (is = 6 (length (orrery/adapter:pwam-rows report)))))

(define-test (playwright-attestation-merger-suite fail-on-missing-scenario)
  "Missing S3 => report fails with S3 in missing-scenarios."
  (let* ((ledger (%mk-partial-attestation-ledger))
         (report (orrery/adapter:merge-playwright-attestations->envelope ledger)))
    (false (orrery/adapter:pwam-pass-p report))
    (true (find "S3" (orrery/adapter:pwam-missing-scenarios report) :test #'string=))
    (is = 1 (length (orrery/adapter:pwam-missing-scenarios report)))))

(define-test (playwright-attestation-merger-suite fail-on-command-drift)
  "S4 command drift => report fails with S4 in drift-scenarios."
  (let* ((ledger (%mk-drift-attestation-ledger))
         (report (orrery/adapter:merge-playwright-attestations->envelope ledger)))
    (false (orrery/adapter:pwam-pass-p report))
    (true (find "S4" (orrery/adapter:pwam-drift-scenarios report) :test #'string=))
    (is = 1 (length (orrery/adapter:pwam-drift-scenarios report)))))

(define-test (playwright-attestation-merger-suite fail-on-missing-trace)
  "S5 missing trace => row has :missing-trace taxonomy."
  (let* ((ledger (%mk-missing-artifact-ledger))
         (report (orrery/adapter:merge-playwright-attestations->envelope ledger))
         (s5-row (find "S5" (orrery/adapter:pwam-rows report)
                       :key #'orrery/adapter:pwer-scenario-id
                       :test #'string=)))
    (false (orrery/adapter:pwam-pass-p report))
    (true s5-row)
    (false (orrery/adapter:pwer-trace-present-p s5-row))
    (true (find :missing-trace (orrery/adapter:pwer-taxonomy-codes s5-row)))))

(define-test (playwright-attestation-merger-suite json-includes-required-fields)
  "JSON output includes all required envelope fields."
  (let* ((ledger (%mk-full-attestation-ledger))
         (report (orrery/adapter:merge-playwright-attestations->envelope ledger))
         (json (orrery/adapter:pw-attestation-merger-report->json report)))
    (true (search "\"pass\":" json))
    (true (search "\"command_match\":" json))
    (true (search "\"command_hash\":" json))
    (true (search "\"expected_hash\":" json))
    (true (search "\"missing_scenarios\":" json))
    (true (search "\"drift_scenarios\":" json))
    (true (search "\"rows\":" json))
    (true (search "\"timestamp\":" json))))

(define-test (playwright-attestation-merger-suite json-row-fields)
  "JSON rows include scenario, pass, hashes, artifacts, taxonomy."
  (let* ((ledger (%mk-full-attestation-ledger))
         (report (orrery/adapter:merge-playwright-attestations->envelope ledger))
         (json (orrery/adapter:pw-attestation-merger-report->json report)))
    (true (search "\"scenario\":" json))
    (true (search "\"pass\":" json))
    (true (search "\"command_hash\":" json))
    (true (search "\"expected_hash\":" json))
    (true (search "\"hash_match\":" json))
    (true (search "\"screenshot_present\":" json))
    (true (search "\"trace_present\":" json))
    (true (search "\"taxonomy\":" json))))

(define-test (playwright-attestation-merger-suite json-drift-includes-taxonomy)
  "JSON from drift ledger includes :command-drift taxonomy."
  (let* ((ledger (%mk-drift-attestation-ledger))
         (report (orrery/adapter:merge-playwright-attestations->envelope ledger))
         (json (orrery/adapter:pw-attestation-merger-report->json report)))
    (false (orrery/adapter:pwam-pass-p report))
    (true (search "\"command-drift\"" json))))
