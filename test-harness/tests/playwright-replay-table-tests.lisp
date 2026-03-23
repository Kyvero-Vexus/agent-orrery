;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-replay-table-tests.lisp — Tests for S1-S6 replay table + verifier hooks
;;; Bead: agent-orrery-0xa

(in-package #:orrery/harness-tests)

(define-test playwright-replay-table-suite)

(defun %mk-rpt-dir (prefix)
  (let ((d (format nil "/tmp/orrery-rpt-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %cleanup-rpt (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

;; Empty dir => all rows fail => table pass=false
(define-test (playwright-replay-table-suite empty-dir-fail)
  (let* ((d (%mk-rpt-dir "empty"))
         (table (orrery/adapter:compile-playwright-replay-table d "cd e2e && ./run-e2e.sh")))
    (unwind-protect
         (progn
           (false (orrery/adapter:prt-pass-p table))
           (is = 6 (orrery/adapter:prt-fail-count table))
           (is = 6 (length (orrery/adapter:prt-rows table))))
      (%cleanup-rpt d))))

;; Failure codes present on missing artifacts
(define-test (playwright-replay-table-suite failure-codes-on-missing)
  (let* ((d (%mk-rpt-dir "miss"))
         (table (orrery/adapter:compile-playwright-replay-table d "cd e2e && ./run-e2e.sh")))
    (unwind-protect
         (let ((row (first (orrery/adapter:prt-rows table))))
           (true (not (null (orrery/adapter:prr-failure-codes row))))
           (true (find-if (lambda (c) (search "REPLAY_MISSING" c))
                          (orrery/adapter:prr-failure-codes row))))
      (%cleanup-rpt d))))

;; JSON fields
(define-test (playwright-replay-table-suite json-fields)
  (let* ((d (%mk-rpt-dir "json"))
         (table (orrery/adapter:compile-playwright-replay-table d "cd e2e && ./run-e2e.sh"))
         (json (orrery/adapter:playwright-replay-table->json table)))
    (unwind-protect
         (progn
           (true (search "\"pass\":" json))
           (true (search "\"command_hash\":" json))
           (true (search "\"fail_count\":" json))
           (true (search "\"rows\":" json))
           (true (search "\"preflight_ok\":" json))
           (true (search "\"transcript_hash\":" json)))
      (%cleanup-rpt d))))

;; Preflight record from row
(define-test (playwright-replay-table-suite preflight-record-from-row)
  (let* ((row (orrery/adapter::make-playwright-replay-row
               :scenario-id "S2"
               :command "cd e2e && ./run-e2e.sh"
               :command-hash 42
               :screenshot-path ""
               :trace-path ""
               :transcript-hash 0
               :preflight-ok-p nil
               :failure-codes '("E4_REPLAY_MISSING_SCR_S2")))
         (rec (orrery/adapter:replay-row->preflight-record row)))
    (false (orrery/adapter:ppr-gate-pass-p rec))
    (is string= "S2" (orrery/adapter:ppr-scenario-id rec))
    (true (not (null (orrery/adapter:ppr-reason-codes rec))))))

;; Command hash pinned to canonical
(define-test (playwright-replay-table-suite canonical-command-hash)
  (let* ((d (%mk-rpt-dir "hash"))
         (table (orrery/adapter:compile-playwright-replay-table
                 d orrery/adapter:*playwright-canonical-command*)))
    (unwind-protect
         (is = orrery/adapter:*playwright-canonical-command-hash*
             (orrery/adapter:prt-command-hash table))
      (%cleanup-rpt d))))
