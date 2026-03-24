;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-command-fingerprint-baseline-ledger-tests.lisp — Tests for T1-T6 baseline ledger
;;; Bead: agent-orrery-0ko9

(in-package #:orrery/harness-tests)

(define-test t1-t6-baseline-ledger-suite)

(defun %make-test-journal (command same-digests-p)
  "Build a t1-t6-replay-journal for baseline tests."
  (declare (ignore command same-digests-p))
  (orrery/adapter::make-empty-journal))

;; fingerprint-string produces consistent output
(define-test (t1-t6-baseline-ledger-suite fingerprint-string-stable)
  (let ((fp1 (orrery/adapter:fingerprint-string "hello"))
        (fp2 (orrery/adapter:fingerprint-string "hello")))
    (is string= fp1 fp2)
    (true (plusp (length fp1)))))

;; capture-baseline-snapshot builds a snapshot
(define-test (t1-t6-baseline-ledger-suite capture-snapshot)
  (let* ((journal (%make-test-journal "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" t))
         (snap (orrery/adapter:capture-baseline-snapshot journal)))
    (true (orrery/adapter:baseline-snapshot-p snap))
    (true (plusp (length (orrery/adapter:bsnap-version-id snap))))
    (is = 6 (length (orrery/adapter:bsnap-scenario-digests snap)))))

;; append-snapshot builds ledger
(define-test (t1-t6-baseline-ledger-suite append-snapshot)
  (let* ((journal (%make-test-journal "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" t))
         (snap (orrery/adapter:capture-baseline-snapshot journal))
         (ledger (orrery/adapter:append-snapshot
                  (orrery/adapter::make-baseline-ledger) snap)))
    (is = 1 (orrery/adapter:bldr-snapshot-count ledger))
    (is string= (orrery/adapter:bsnap-version-id snap)
        (orrery/adapter:bldr-latest-version-id ledger))))

;; build-baseline-drift-report: same snapshot => :clean
(define-test (t1-t6-baseline-ledger-suite same-snapshot-clean)
  (let* ((journal (%make-test-journal "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" t))
         (snap (orrery/adapter:capture-baseline-snapshot journal))
         (report (orrery/adapter:build-baseline-drift-report snap snap)))
    (is eq :clean (orrery/adapter:bdr-verdict report))
    (is = 0 (orrery/adapter:bdr-drifted-count report))))

;; JSON output
(define-test (t1-t6-baseline-ledger-suite report-json-fields)
  (let* ((journal (%make-test-journal "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" t))
         (snap (orrery/adapter:capture-baseline-snapshot journal))
         (report (orrery/adapter:build-baseline-drift-report snap snap))
         (json (orrery/adapter:baseline-drift-report->json report)))
    (true (search "\"verdict\":" json))
    (true (search "\"drifted_count\":" json))
    (true (search "\"deltas\":" json))))
