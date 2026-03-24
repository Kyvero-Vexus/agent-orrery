;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-env-fingerprint-normalizer-tests.lisp
;;;   Tests for T1-T6 env-fingerprint normalizer + drift explainer.
;;;
;;; Bead: agent-orrery-t1yb

(in-package #:orrery/harness-tests)

(define-test t1-t6-env-fingerprint-normalizer-suite)

;;; ── helpers ──────────────────────────────────────────────────────────────────

(defun %make-test-fp (&key (lisp-impl "SBCL 2.4.0")
                           (os-info "Linux")
                           (harness-flags nil))
  (orrery/adapter:make-env-fingerprint
   :lisp-impl lisp-impl
   :os-info os-info
   :harness-flags harness-flags
   :deterministic-command "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
   :command-fingerprint (format nil "~16,'0X"
                                (sxhash "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
   :captured-at (get-universal-time)))

;;; ── capture + normalize ──────────────────────────────────────────────────────

(define-test (t1-t6-env-fingerprint-normalizer-suite capture-env-fingerprint)
  (let ((fp (orrery/adapter:capture-env-fingerprint)))
    (false (string= "" (orrery/adapter:efp-lisp-impl fp))
           "lisp-impl is non-empty")
    (is equal "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
        (orrery/adapter:efp-deterministic-command fp)
        "canonical command locked")
    (false (string= "" (orrery/adapter:efp-command-fingerprint fp))
           "command fingerprint non-empty")))

(define-test (t1-t6-env-fingerprint-normalizer-suite normalize-trims-whitespace)
  (let* ((fp (orrery/adapter:make-env-fingerprint
              :lisp-impl "  SBCL 2.4.0  "
              :os-info "  Linux  "
              :harness-flags nil
              :deterministic-command "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
              :command-fingerprint ""
              :captured-at 0))
         (normalized (orrery/adapter:normalize-env-fingerprint fp)))
    (is equal "SBCL 2.4.0" (orrery/adapter:efp-lisp-impl normalized)
        "lisp-impl trimmed")
    (is equal "Linux" (orrery/adapter:efp-os-info normalized)
        "os-info trimmed")))

;;; ── stable diff ──────────────────────────────────────────────────────────────

(define-test (t1-t6-env-fingerprint-normalizer-suite diff-stable-when-identical)
  (let* ((fp1 (%make-test-fp))
         (fp2 (%make-test-fp))
         (report (orrery/adapter:build-env-drift-report fp1 fp2)))
    (is eq :stable (orrery/adapter:evaluate-env-drift-gate report)
        "identical fingerprints yield :stable gate")
    (is = 0 (orrery/adapter:ereport-drift-count report)
        "zero drift records for identical fingerprints")))

;;; ── env-mismatch drift ───────────────────────────────────────────────────────

(define-test (t1-t6-env-fingerprint-normalizer-suite diff-detects-lisp-impl-change)
  (let* ((fp1 (%make-test-fp :lisp-impl "SBCL 2.3.0"))
         (fp2 (%make-test-fp :lisp-impl "SBCL 2.4.0"))
         (report (orrery/adapter:build-env-drift-report fp1 fp2)))
    (is eq :drifted (orrery/adapter:evaluate-env-drift-gate report)
        "lisp-impl change yields :drifted")
    (is = 1 (orrery/adapter:ereport-drift-count report)
        "one drift record for lisp-impl change")
    (let ((rec (first (orrery/adapter:ereport-records report))))
      (is eq :env-mismatch (orrery/adapter:edr-drift-class rec)
          "drift class is :env-mismatch"))))

;;; ── command-drift → rejected ─────────────────────────────────────────────────

(define-test (t1-t6-env-fingerprint-normalizer-suite diff-rejects-on-command-drift)
  (let* ((fp1 (%make-test-fp))
         (fp2 (orrery/adapter:make-env-fingerprint
               :lisp-impl "SBCL 2.4.0"
               :os-info "Linux"
               :harness-flags nil
               :deterministic-command "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
               :command-fingerprint "DEADBEEF00000000"  ; forced drift
               :captured-at (get-universal-time)))
         (report (orrery/adapter:build-env-drift-report fp1 fp2)))
    (is eq :rejected (orrery/adapter:evaluate-env-drift-gate report)
        "command fingerprint drift yields :rejected (fail closed)")))

;;; ── flag drift ───────────────────────────────────────────────────────────────

(define-test (t1-t6-env-fingerprint-normalizer-suite diff-detects-flag-change)
  (let* ((fp1 (%make-test-fp :harness-flags '(("headless" . "true") ("timeout" . "30"))))
         (fp2 (%make-test-fp :harness-flags '(("headless" . "false") ("timeout" . "30"))))
         (report (orrery/adapter:build-env-drift-report fp1 fp2)))
    (is eq :drifted (orrery/adapter:evaluate-env-drift-gate report)
        "flag change yields :drifted")
    (let ((flag-recs (remove :flag-drift (orrery/adapter:ereport-records report)
                             :test-not #'eq
                             :key #'orrery/adapter:edr-drift-class)))
      (is = 1 (length flag-recs)
          "one flag-drift record"))))

;;; ── JSON serialization ───────────────────────────────────────────────────────

(define-test (t1-t6-env-fingerprint-normalizer-suite env-fingerprint-json)
  (let* ((fp (%make-test-fp))
         (json (orrery/adapter:env-fingerprint->json fp)))
    (true (search "\"lisp_impl\"" json) "JSON has lisp_impl")
    (true (search "\"command_fingerprint\"" json) "JSON has command_fingerprint")
    (true (search "run-tui-e2e-t1-t6" json) "JSON contains canonical command")))

(define-test (t1-t6-env-fingerprint-normalizer-suite drift-report-json-stable)
  (let* ((fp1 (%make-test-fp))
         (fp2 (%make-test-fp))
         (report (orrery/adapter:build-env-drift-report fp1 fp2))
         (json (orrery/adapter:env-drift-report->json report)))
    (true (search "\"gate_verdict\":\"STABLE\"" json)
          "JSON gate_verdict is STABLE")))

(define-test (t1-t6-env-fingerprint-normalizer-suite drift-report-json-rejected)
  (let* ((fp1 (%make-test-fp))
         (fp2 (orrery/adapter:make-env-fingerprint
               :lisp-impl "SBCL 2.4.0" :os-info "Linux" :harness-flags nil
               :deterministic-command "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
               :command-fingerprint "DEADBEEF00000000"
               :captured-at (get-universal-time)))
         (report (orrery/adapter:build-env-drift-report fp1 fp2))
         (json (orrery/adapter:env-drift-report->json report)))
    (true (search "\"gate_verdict\":\"REJECTED\"" json)
          "JSON gate_verdict is REJECTED on command drift")))
