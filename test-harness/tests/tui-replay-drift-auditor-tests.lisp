;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-replay-drift-auditor-tests.lisp — Tests for T1-T6 replay drift auditor
;;; Bead: agent-orrery-9vaf

(in-package #:orrery/harness-tests)

(define-test tui-replay-drift-auditor-suite)

(defun %make-test-batch (texts command)
  "Build a fingerprint batch from list of 6 transcript strings."
  (let ((fps (mapcar (lambda (sid text)
                       (orrery/adapter:build-tui-transcript-fingerprint sid text command))
                     orrery/adapter:*mcp-tui-required-scenarios*
                     texts)))
    (orrery/adapter::make-tui-fingerprint-batch
     :run-id "test"
     :command command
     :command-hash (orrery/adapter:command-fingerprint command)
     :fingerprints fps
     :pass-p t
     :timestamp 0)))

;; Nil baseline (first run) => no drift => pass=true
(define-test (tui-replay-drift-auditor-suite nil-baseline-no-drift)
  (let* ((texts (loop repeat 6 collect "line1\nline2\n"))
         (batch (%make-test-batch texts orrery/adapter:*mcp-tui-deterministic-command*))
         (v (orrery/adapter:audit-tui-replay-drift batch nil)))
    (true (orrery/adapter:trdv-pass-p v))
    (is = 0 (orrery/adapter:trdv-drift-count v))))

;; Same baseline as current => no drift
(define-test (tui-replay-drift-auditor-suite same-baseline-no-drift)
  (let* ((texts (loop repeat 6 collect "stable content\n"))
         (batch (%make-test-batch texts orrery/adapter:*mcp-tui-deterministic-command*))
         (v (orrery/adapter:audit-tui-replay-drift batch batch)))
    (true (orrery/adapter:trdv-pass-p v))
    (is = 0 (orrery/adapter:trdv-drift-count v))))

;; Different baseline => fingerprint drift => pass=false
(define-test (tui-replay-drift-auditor-suite changed-content-drift)
  (let* ((old-texts (loop repeat 6 collect "old content\n"))
         (new-texts (loop repeat 6 collect "new different content\n"))
         (old-batch (%make-test-batch old-texts orrery/adapter:*mcp-tui-deterministic-command*))
         (new-batch (%make-test-batch new-texts orrery/adapter:*mcp-tui-deterministic-command*))
         (v (orrery/adapter:audit-tui-replay-drift new-batch old-batch)))
    (false (orrery/adapter:trdv-pass-p v))
    (true (> (orrery/adapter:trdv-drift-count v) 0))))

;; JSON fields
(define-test (tui-replay-drift-auditor-suite json-fields)
  (let* ((texts (loop repeat 6 collect "x\n"))
         (batch (%make-test-batch texts orrery/adapter:*mcp-tui-deterministic-command*))
         (v (orrery/adapter:audit-tui-replay-drift batch nil))
         (json (orrery/adapter:tui-replay-drift-verdict->json v)))
    (true (search "\"pass\":" json))
    (true (search "\"drift_count\":" json))
    (true (search "\"command_hash\":" json))
    (true (search "\"rows\":" json))
    (true (search "\"drift_codes\":" json))))

;; Drift codes contain scenario ID
(define-test (tui-replay-drift-auditor-suite drift-codes-contain-scenario)
  (let* ((old-texts (loop repeat 6 collect "v1\n"))
         (new-texts (loop repeat 6 collect "v2 changed\n"))
         (old-batch (%make-test-batch old-texts orrery/adapter:*mcp-tui-deterministic-command*))
         (new-batch (%make-test-batch new-texts orrery/adapter:*mcp-tui-deterministic-command*))
         (v (orrery/adapter:audit-tui-replay-drift new-batch old-batch))
         (row (first (orrery/adapter:trdv-rows v))))
    (true (find-if (lambda (c) (search "T1" c))
                   (orrery/adapter:tdr-drift-codes row)))))
