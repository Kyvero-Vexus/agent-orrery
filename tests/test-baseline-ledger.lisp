;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; test-baseline-ledger.lisp — smoke tests for T1-T6 command-fingerprint
;;; baseline ledger (bead agent-orrery-0ko9)

(in-package #:orrery/adapter)

(defun run-baseline-ledger-tests ()
  (let ((errors '()))
    ;; ── helper ─────────────────────────────────────────────────────────────
    (flet ((assert-equal (label expected actual)
             (unless (equal expected actual)
               (push (format nil "FAIL ~A: expected ~S got ~S" label expected actual) errors)))
           (assert-true (label val)
             (unless val
               (push (format nil "FAIL ~A: expected non-NIL" label) errors))))

      ;; ── Build a synthetic journal with T1..T6 ──────────────────────────
      (let* ((rows
               (mapcar (lambda (sid)
                         (make-t1-t6-replay-journal-row
                          :scenario-id sid
                          :transcript-digest
                          (make-replay-transcript-digest
                           :scenario-id sid
                           :digest (format nil "digest-~A" sid)
                           :line-count 10
                           :captured-at "")
                          :verdict :pass))
                       '(:T1 :T2 :T3 :T4 :T5 :T6)))
             (journal (make-t1-t6-replay-journal
                       :rows rows
                       :created-at "2026-01-01"
                       :deterministic-command *canonical-t1-t6-command*))
             (snap1 (capture-baseline-snapshot journal))
             (ledger (append-snapshot (make-baseline-ledger
                                       :snapshots '()
                                       :latest-version-id ""
                                       :snapshot-count 0)
                                      snap1)))

        (assert-true  "snapshot canonical"  (bsnap-canonical-p snap1))
        (assert-equal "snapshot version non-empty" nil (string= "" (bsnap-version-id snap1)))
        (assert-equal "ledger count" 1 (bldr-snapshot-count ledger))
        (assert-equal "ledger latest" (bsnap-version-id snap1) (bldr-latest-version-id ledger))

        ;; ── Second snapshot with T3 digest changed ─────────────────────
        (let* ((rows2
                 (mapcar (lambda (sid)
                           (make-t1-t6-replay-journal-row
                            :scenario-id sid
                            :transcript-digest
                            (make-replay-transcript-digest
                             :scenario-id sid
                             :digest (if (eq sid :T3)
                                         "NEW-DIGEST-T3"
                                         (format nil "digest-~A" sid))
                             :line-count 10
                             :captured-at "")
                            :verdict :pass))
                         '(:T1 :T2 :T3 :T4 :T5 :T6)))
               (journal2 (make-t1-t6-replay-journal
                          :rows rows2
                          :created-at "2026-01-02"
                          :deterministic-command *canonical-t1-t6-command*))
               (snap2  (capture-baseline-snapshot journal2))
               (report (build-baseline-drift-report snap1 snap2)))

          (assert-equal "verdict drifted" :drifted (bdr-verdict report))
          (assert-equal "drifted count" 1 (bdr-drifted-count report))

          (let* ((t3-delta (find :T3 (bdr-deltas report) :key #'ddelta-scenario-id)))
            (assert-true "T3 delta exists" t3-delta)
            (assert-equal "T3 status" :drifted (ddelta-status t3-delta))
            (assert-equal "T3 new-digest" "NEW-DIGEST-T3" (ddelta-new-digest t3-delta)))

          ;; ── JSON round-trip smoke ──────────────────────────────────────
          (let ((json (baseline-drift-report->json report)))
            (assert-true "json non-empty" (> (length json) 10))
            (assert-true "json has verdict" (search "drifted" json)))

          (let ((ljson (baseline-ledger->json ledger)))
            (assert-true "ledger json non-empty" (> (length ljson) 10)))))

      ;; ── Non-canonical command → rejected ──────────────────────────────
      (let* ((bad-journal (make-t1-t6-replay-journal
                           :rows '()
                           :created-at ""
                           :deterministic-command "echo bad"))
             (bad-snap (capture-baseline-snapshot bad-journal))
             (good-rows
               (mapcar (lambda (sid)
                         (make-t1-t6-replay-journal-row
                          :scenario-id sid
                          :transcript-digest
                          (make-replay-transcript-digest
                           :scenario-id sid :digest "d" :line-count 0 :captured-at "")
                          :verdict :pass))
                       '(:T1 :T2 :T3 :T4 :T5 :T6)))
             (good-journal (make-t1-t6-replay-journal
                            :rows good-rows
                            :created-at ""
                            :deterministic-command *canonical-t1-t6-command*))
             (good-snap (capture-baseline-snapshot good-journal))
             (report (build-baseline-drift-report bad-snap good-snap)))
        (assert-equal "non-canonical → rejected" :rejected (bdr-verdict report))))

    (if errors
        (progn
          (format t "~%BASELINE-LEDGER TESTS FAILED:~%")
          (dolist (e errors) (format t "  ~A~%" e))
          nil)
        (progn
          (format t "~%BASELINE-LEDGER TESTS: all passed~%")
          t))))
