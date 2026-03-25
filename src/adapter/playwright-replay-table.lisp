;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-replay-table.lisp — typed S1-S6 deterministic evidence replay table + verifier hooks
;;; Bead: agent-orrery-0xa

(in-package #:orrery/adapter)

;;; ── Replay row ───────────────────────────────────────────────────────────────

(defstruct (playwright-replay-row (:conc-name prr-))
  "One row in the S1-S6 deterministic replay table."
  (scenario-id      ""    :type string)
  (command          ""    :type string)
  (command-hash     0     :type integer)
  (screenshot-path  ""    :type string)
  (trace-path       ""    :type string)
  (transcript-hash  0     :type integer)
  (preflight-ok-p   nil   :type boolean)
  (failure-codes    nil   :type list))

;;; ── Replay table ─────────────────────────────────────────────────────────────

(defstruct (playwright-replay-table (:conc-name prt-))
  "Typed S1-S6 replay table with aggregate preflight verdict."
  (run-id        ""    :type string)
  (command       ""    :type string)
  (command-hash  0     :type integer)
  (rows          nil   :type list)   ; list of playwright-replay-row
  (pass-p        nil   :type boolean)
  (fail-count    0     :type integer)
  (timestamp     0     :type integer))

;;; ── Preflight hook result ────────────────────────────────────────────────────

(defstruct (playwright-preflight-hook (:conc-name pph-))
  "Machine-checkable preflight hook result for one S1-S6 scenario."
  (scenario-id    ""     :type string)
  (gate-pass-p    nil    :type boolean)
  (reason-codes   nil    :type list)
  (detail         ""     :type string))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string string) (values playwright-replay-row &optional))
        build-playwright-replay-row)
 (ftype (function (string string) (values playwright-replay-table &optional))
        compile-playwright-replay-table)
 (ftype (function (playwright-replay-row) (values playwright-preflight-hook &optional))
        replay-row->preflight-record)
 (ftype (function (playwright-replay-table) (values string &optional))
        playwright-replay-table->json))

;;; ── Builders ─────────────────────────────────────────────────────────────────

(defun build-playwright-replay-row (artifact-root scenario-id)
  (declare (type string artifact-root scenario-id)
           (optimize (safety 3)))
  (let* ((manifest  (compile-playwright-evidence-manifest artifact-root *playwright-canonical-command*))
         (scr       (find-web-scenario-artifact-path manifest scenario-id :screenshot))
         (trc       (find-web-scenario-artifact-path manifest scenario-id :trace))
         (cmd       *playwright-canonical-command*)
         (cmd-hash  *playwright-canonical-command-hash*)
         (scr-ok    (plusp (length scr)))
         (trc-ok    (plusp (length trc)))
         (tx-hash   (if scr-ok (sxhash scr) 0))
         (ok        (and scr-ok trc-ok))
         (codes     (append
                     (unless scr-ok (list (format nil "E4_REPLAY_MISSING_SCR_~A" scenario-id)))
                     (unless trc-ok (list (format nil "E4_REPLAY_MISSING_TRC_~A" scenario-id))))))
    (make-playwright-replay-row
     :scenario-id     scenario-id
     :command         cmd
     :command-hash    cmd-hash
     :screenshot-path scr
     :trace-path      trc
     :transcript-hash tx-hash
     :preflight-ok-p  ok
     :failure-codes   codes)))

(defun compile-playwright-replay-table (artifact-root command)
  "Build typed S1-S6 replay table. Command must match canonical; drift sets fail codes."
  (declare (type string artifact-root command)
           (optimize (safety 3)))
  (let* ((rows      (mapcar (lambda (sid) (build-playwright-replay-row artifact-root sid))
                            *playwright-required-scenarios*))
         (fail-cnt  (count-if (lambda (r) (not (prr-preflight-ok-p r))) rows))
         (pass      (zerop fail-cnt)))
    (make-playwright-replay-table
     :run-id       (format nil "prt-~D" (get-universal-time))
     :command      command
     :command-hash (command-fingerprint command)
     :rows         rows
     :pass-p       pass
     :fail-count   fail-cnt
     :timestamp    (get-universal-time))))

(defun replay-row->preflight-record (row)
  "Convert one replay row to a machine-checkable preflight record."
  (declare (type playwright-replay-row row))
  (make-playwright-preflight-hook
   :scenario-id  (prr-scenario-id row)
   :gate-pass-p  (prr-preflight-ok-p row)
   :reason-codes (prr-failure-codes row)
   :detail       (if (prr-preflight-ok-p row)
                     (format nil "~A: preflight ok cmd_hash=~D"
                             (prr-scenario-id row) (prr-command-hash row))
                     (format nil "~A: preflight fail ~{~A~^,~}"
                             (prr-scenario-id row) (prr-failure-codes row)))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %prr->json (row)
  (declare (type playwright-replay-row row))
  (with-output-to-string (out)
    (format out
            "{\"scenario\":\"~A\",\"command_hash\":~D,\"transcript_hash\":~D,\"preflight_ok\":~A,\"failure_codes\":["
            (prr-scenario-id row)
            (prr-command-hash row)
            (prr-transcript-hash row)
            (if (prr-preflight-ok-p row) "true" "false"))
    (loop for c in (prr-failure-codes row)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" c)))
    (write-string "]}" out)))

(defun playwright-replay-table->json (table)
  "Serialise PLAYWRIGHT-REPLAY-TABLE to machine-readable JSON."
  (declare (type playwright-replay-table table))
  (with-output-to-string (out)
    (format out
            "{\"run_id\":\"~A\",\"command_hash\":~D,\"pass\":~A,\"fail_count\":~D,\"timestamp\":~D,\"rows\":["
            (prt-run-id table)
            (prt-command-hash table)
            (if (prt-pass-p table) "true" "false")
            (prt-fail-count table)
            (prt-timestamp table))
    (loop for row in (prt-rows table)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%prr->json row) out)))
    (write-string "]}" out)))

;;; ── Compatibility aliases ────────────────────────────────────────────────────
;;; playwright-verifier-hook-adapter uses ppr-* names; provide them here.

(deftype playwright-preflight-record () 'playwright-preflight-hook)

(declaim (inline ppr-scenario-id ppr-gate-pass-p ppr-reason-codes ppr-detail))
(defun ppr-scenario-id  (r) (pph-scenario-id  r))
(defun ppr-gate-pass-p  (r) (pph-gate-pass-p  r))
(defun ppr-reason-codes (r) (pph-reason-codes r))
(defun ppr-detail       (r) (pph-detail       r))
