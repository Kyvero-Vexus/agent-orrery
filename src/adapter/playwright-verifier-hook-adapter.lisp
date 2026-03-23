;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-verifier-hook-adapter.lisp — typed Playwright verifier-hook adapter + JSON preflight output
;;; Bead: agent-orrery-3j2
;;;
;;; Consumes playwright-replay-table verifier hooks and emits a deterministic
;;; JSON preflight payload. Fail-closed: any row failing preflight propagates to
;;; the overall verdict.
;;;
;;; Deterministic command: cd e2e && bash run-e2e.sh

(in-package #:orrery/adapter)

;;; ── Types ────────────────────────────────────────────────────────────────────

(defstruct (playwright-hook-verdict (:conc-name phv-))
  "Aggregate preflight verdict from S1-S6 Playwright verifier hooks."
  (run-id          ""    :type string)
  (command         ""    :type string)
  (command-hash    0     :type integer)
  (records         nil   :type list)   ; list of playwright-preflight-record
  (pass-p          nil   :type boolean)
  (fail-count      0     :type integer)
  (closure-verdict :open :type symbol) ; :CLOSED | :OPEN
  (timestamp       0     :type integer)
  (detail          ""    :type string))

;;; ── Declaims ─────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (playwright-replay-table) (values playwright-hook-verdict &optional))
        run-playwright-s1-s6-hook-preflight)
 (ftype (function (playwright-hook-verdict) (values string &optional))
        playwright-hook-verdict->json))

;;; ── Constants ────────────────────────────────────────────────────────────────

(defparameter *playwright-canonical-deterministic-command*
  "cd e2e && bash run-e2e.sh"
  "Canonical deterministic command for S1-S6 Playwright runs.")

;;; ── Implementation ───────────────────────────────────────────────────────────

(defun run-playwright-s1-s6-hook-preflight (table)
  "Run verifier hooks over Playwright S1-S6 replay table and emit preflight verdict."
  (declare (type playwright-replay-table table)
           (optimize (safety 3)))
  (let* ((records      (mapcar #'replay-row->preflight-record
                               (prt-rows table)))
         (fail-count   (count-if-not #'ppr-gate-pass-p records))
         (pass-p       (zerop fail-count))
         (verdict      (if pass-p :CLOSED :OPEN))
         (cmd          *playwright-canonical-deterministic-command*)
         (cmd-hash     (sxhash cmd))
         (timestamp    (get-universal-time)))
    (make-playwright-hook-verdict
     :run-id          (format nil "playwright-preflight-~D" timestamp)
     :command         cmd
     :command-hash    cmd-hash
     :records         records
     :pass-p          pass-p
     :fail-count      fail-count
     :closure-verdict verdict
     :timestamp       timestamp
     :detail          (if pass-p
                          "ALL_S1_S6_PREFLIGHT_PASS"
                          (format nil "PREFLIGHT_FAIL: ~D scenarios" fail-count)))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %ppr->json (r)
  (declare (type playwright-preflight-record r))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"pass\":~A,\"fail_codes\":~D,\"detail\":\"~A\"}"
            (ppr-scenario-id r)
            (if (ppr-gate-pass-p r) "true" "false")
            (length (ppr-reason-codes r))
            (ppr-detail r))))

(defun playwright-hook-verdict->json (verdict)
  "Serialize Playwright S1-S6 preflight verdict to deterministic JSON."
  (declare (type playwright-hook-verdict verdict))
  (with-output-to-string (out)
    (format out "{\"run_id\":\"~A\",\"command\":\"~A\",\"command_hash\":~D,\"pass\":~A,\"fail_count\":~D,\"closure_verdict\":\"~A\",\"timestamp\":~D,\"detail\":\"~A\",\"records\":["
            (phv-run-id verdict)
            (phv-command verdict)
            (phv-command-hash verdict)
            (if (phv-pass-p verdict) "true" "false")
            (phv-fail-count verdict)
            (phv-closure-verdict verdict)
            (phv-timestamp verdict)
            (phv-detail verdict))
    (loop for r in (phv-records verdict)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%ppr->json r) out)))
    (write-string "]}" out)))
