;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-cmd-table-verifier-tests.lisp — Tests for S1-S6 command-table verifier gate
;;; Bead: agent-orrery-91gj

(in-package #:orrery/harness-tests)

(define-test playwright-cmd-table-verifier-suite)

(defun %make-ledger-with-hash (hash)
  "Build a minimal playwright-scenario-ledger with all S1-S6 attestations using HASH."
  (let ((atts (mapcar
               (lambda (sid)
                 (orrery/adapter::make-web-scenario-attestation
                  :scenario-id sid
                  :command-fingerprint hash
                  :screenshot-path (format nil "/tmp/~A.png" sid)
                  :trace-path (format nil "/tmp/~A.zip" sid)
                  :screenshot-hash "h1"
                  :trace-hash "h2"
                  :attested-p t))
               orrery/adapter:*playwright-required-scenarios*)))
    (orrery/adapter::make-playwright-scenario-ledger
     :run-id "test-run"
     :command orrery/adapter:*playwright-canonical-command*
     :attestations atts
     :timestamp (get-universal-time))))

;; Pass: canonical hash => all rows green, verdict pass=true
(define-test (playwright-cmd-table-verifier-suite canonical-hash-pass)
  (let* ((ledger (%make-ledger-with-hash orrery/adapter:*playwright-canonical-command-hash*))
         (verdict (orrery/adapter:verify-playwright-command-table ledger)))
    (true (orrery/adapter:pctv-pass-p verdict))
    (is = 0 (orrery/adapter:pctv-mismatch-count verdict))
    (is = 0 (orrery/adapter:pctv-missing-count verdict))
    (is = 6 (length (orrery/adapter:pctv-rows verdict)))))

;; Fail: wrong hash => drift taxonomy on every scenario, verdict pass=false
(define-test (playwright-cmd-table-verifier-suite wrong-hash-drift)
  (let* ((ledger (%make-ledger-with-hash 999999))
         (verdict (orrery/adapter:verify-playwright-command-table ledger)))
    (false (orrery/adapter:pctv-pass-p verdict))
    (is = 6 (orrery/adapter:pctv-mismatch-count verdict))
    (is = 0 (orrery/adapter:pctv-missing-count verdict))
    (true (every (lambda (r)
                   (find-if (lambda (c) (search "DRIFT" c))
                            (orrery/adapter:pctr-taxonomy-codes r)))
                 (orrery/adapter:pctv-rows verdict)))))

;; Fail: nil ledger => all missing, verdict pass=false
(define-test (playwright-cmd-table-verifier-suite nil-ledger-all-missing)
  (let ((verdict (orrery/adapter:verify-playwright-command-table nil)))
    (false (orrery/adapter:pctv-pass-p verdict))
    (is = 6 (orrery/adapter:pctv-mismatch-count verdict))
    (is = 6 (orrery/adapter:pctv-missing-count verdict))))

;; JSON: verdict->json emits expected fields
(define-test (playwright-cmd-table-verifier-suite json-fields-present)
  (let* ((ledger (%make-ledger-with-hash orrery/adapter:*playwright-canonical-command-hash*))
         (verdict (orrery/adapter:verify-playwright-command-table ledger))
         (json (orrery/adapter:playwright-cmd-table-verdict->json verdict)))
    (true (search "\"pass\":" json))
    (true (search "\"mismatch_count\":" json))
    (true (search "\"missing_count\":" json))
    (true (search "\"rows\":" json))
    (true (search "\"command_hash\":" json))
    (true (search "\"expected_hash\":" json))
    (true (search "\"taxonomy\":" json))))

;; Per-row taxonomy code format
(define-test (playwright-cmd-table-verifier-suite taxonomy-code-format)
  (let* ((ledger (%make-ledger-with-hash 0))
         (verdict (orrery/adapter:verify-playwright-command-table ledger))
         (row (first (orrery/adapter:pctv-rows verdict)))
         (code (first (orrery/adapter:pctr-taxonomy-codes row))))
    (true (or (search "DRIFT" code) (search "MISSING" code)))))
