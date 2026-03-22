;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-command-table-verifier-tests.lisp — tests for typed S1-S6 command-table verifier gate
;;; Bead: agent-orrery-91gj

(in-package #:orrery/harness-tests)

(define-test playwright-command-table-verifier-suite)

;;; ── helpers ──────────────────────────────────────────────────────────────────

(defun %mk-canonical-ledger ()
  "Build a playwright-scenario-ledger where all 6 scenarios have the canonical command hash."
  (let* ((canonical-cmd orrery/adapter:*playwright-canonical-command*)
         (h              (orrery/adapter:command-fingerprint canonical-cmd))
         (atts           (mapcar (lambda (sid)
                                   (orrery/adapter:make-web-scenario-attestation
                                    :scenario-id        sid
                                    :command-fingerprint h
                                    :screenshot-path    (format nil "/e2e/~A/screenshot.png" sid)
                                    :trace-path         (format nil "/e2e/~A/trace.zip" sid)
                                    :screenshot-hash    "abc"
                                    :trace-hash         "def"
                                    :attested-p         t))
                                 orrery/adapter:*playwright-required-scenarios*)))
    (orrery/adapter:make-playwright-scenario-ledger
     :run-id       "run-test-001"
     :command      canonical-cmd
     :attestations atts
     :timestamp    0)))

(defun %mk-drifted-ledger ()
  "Build a ledger where one scenario has a drifted command hash."
  (let* ((canonical-cmd orrery/adapter:*playwright-canonical-command*)
         (h-good  (orrery/adapter:command-fingerprint canonical-cmd))
         (h-bad   (orrery/adapter:command-fingerprint "cd e2e && ./run-e2e-old.sh"))
         (scenarios orrery/adapter:*playwright-required-scenarios*)
         (atts    (loop for sid in scenarios
                        for i from 0
                        collect (orrery/adapter:make-web-scenario-attestation
                                 :scenario-id        sid
                                 :command-fingerprint (if (= i 2) h-bad h-good)
                                 :screenshot-path    (format nil "/e2e/~A/screenshot.png" sid)
                                 :trace-path         (format nil "/e2e/~A/trace.zip" sid)
                                 :screenshot-hash    "abc"
                                 :trace-hash         "def"
                                 :attested-p         t))))
    (orrery/adapter:make-playwright-scenario-ledger
     :run-id       "run-test-drifted"
     :command      canonical-cmd
     :attestations atts
     :timestamp    0)))

;;; ── tests ────────────────────────────────────────────────────────────────────

(define-test (playwright-command-table-verifier-suite pass-when-all-canonical)
  "All S1-S6 with canonical command hash => verdict passes."
  (let* ((ledger  (%mk-canonical-ledger))
         (verdict (orrery/adapter:verify-playwright-command-table ledger)))
    (true (orrery/adapter:pctv-pass-p verdict))
    (is = 0 (orrery/adapter:pctv-mismatch-count verdict))
    (is = 0 (orrery/adapter:pctv-missing-count verdict))
    (is = 6 (length (orrery/adapter:pctv-rows verdict)))))

(define-test (playwright-command-table-verifier-suite fail-on-nil-ledger)
  "Nil ledger (no attestations) => all 6 rows missing, verdict fails."
  (let ((verdict (orrery/adapter:verify-playwright-command-table nil)))
    (false (orrery/adapter:pctv-pass-p verdict))
    (is = 6 (orrery/adapter:pctv-mismatch-count verdict))
    (is = 6 (orrery/adapter:pctv-missing-count verdict))))

(define-test (playwright-command-table-verifier-suite fail-on-hash-drift)
  "One scenario with drifted hash => verdict fails with taxonomy code."
  (let* ((ledger  (%mk-drifted-ledger))
         (verdict (orrery/adapter:verify-playwright-command-table ledger)))
    (false (orrery/adapter:pctv-pass-p verdict))
    (is = 1 (orrery/adapter:pctv-mismatch-count verdict))
    (is = 0 (orrery/adapter:pctv-missing-count verdict))
    ;; The drifted row should have a non-empty taxonomy
    (let ((bad-row (find-if (lambda (r)
                              (not (null (orrery/adapter:pctr-taxonomy-codes r))))
                            (orrery/adapter:pctv-rows verdict))))
      (true bad-row)
      (false (orrery/adapter:pctr-hash-match-p bad-row)))))

(define-test (playwright-command-table-verifier-suite json-includes-required-fields)
  "JSON output includes pass, mismatch_count, missing_count, rows, taxonomy."
  (let* ((ledger  (%mk-canonical-ledger))
         (verdict (orrery/adapter:verify-playwright-command-table ledger))
         (json    (orrery/adapter:playwright-cmd-table-verdict->json verdict)))
    (true (search "\"pass\":" json))
    (true (search "\"mismatch_count\":" json))
    (true (search "\"missing_count\":" json))
    (true (search "\"rows\":" json))
    (true (search "\"taxonomy\":" json))
    (true (search "\"provided\":" json))
    (true (search "\"deterministic\":" json))
    (true (search "\"command_hash\":" json))
    (true (search "\"expected_hash\":" json))))

(define-test (playwright-command-table-verifier-suite json-fail-includes-taxonomy-codes)
  "JSON from drifted ledger includes E4_CMD_TABLE_DRIFT_* taxonomy code."
  (let* ((ledger  (%mk-drifted-ledger))
         (verdict (orrery/adapter:verify-playwright-command-table ledger))
         (json    (orrery/adapter:playwright-cmd-table-verdict->json verdict)))
    (false (orrery/adapter:pctv-pass-p verdict))
    (true (search "E4_CMD_TABLE_DRIFT_" json))))
