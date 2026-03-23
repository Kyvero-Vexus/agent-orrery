;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-replay-drift-auditor.lisp — typed T1-T6 replay drift auditor + evidence freshness gate
;;; Bead: agent-orrery-9vaf

(in-package #:orrery/adapter)

;;; ── Drift row ────────────────────────────────────────────────────────────────

(defstruct (tui-drift-row (:conc-name tdr-))
  "Per-scenario drift assessment row."
  (scenario-id      ""    :type string)
  (command-hash-ok  nil   :type boolean)
  (fingerprint-ok   nil   :type boolean)
  (fresh-p          nil   :type boolean)
  (baseline-fp      0     :type integer)
  (current-fp       0     :type integer)
  (drift-codes      nil   :type list)
  (detail           ""    :type string))

;;; ── Drift verdict ────────────────────────────────────────────────────────────

(defstruct (tui-replay-drift-verdict (:conc-name trdv-))
  "Aggregate T1-T6 replay drift + freshness verdict."
  (pass-p          nil   :type boolean)
  (drift-count     0     :type (integer 0))
  (stale-count     0     :type (integer 0))
  (rows            nil   :type list)
  (command-hash    0     :type integer)
  (timestamp       0     :type integer)
  (detail          ""    :type string))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string integer integer integer) (values tui-drift-row &optional))
        build-tui-drift-row)
 (ftype (function (tui-fingerprint-batch (or null tui-fingerprint-batch))
                  (values tui-replay-drift-verdict &optional))
        audit-tui-replay-drift)
 (ftype (function (tui-replay-drift-verdict) (values string &optional))
        tui-replay-drift-verdict->json))

;;; ── Row builder ──────────────────────────────────────────────────────────────

(defun build-tui-drift-row (scenario-id current-fp baseline-fp command-hash)
  "Assess drift for one T1-T6 scenario."
  (declare (type string scenario-id)
           (type integer current-fp baseline-fp command-hash)
           (optimize (safety 3)))
  (let* ((canonical-hash  (command-fingerprint *mcp-tui-deterministic-command*))
         (cmd-ok          (= command-hash canonical-hash))
         (fp-ok           (= current-fp baseline-fp))
         (fresh-p         (and cmd-ok fp-ok))
         (codes           (append
                           (unless cmd-ok
                             (list (format nil "E3_DRIFT_CMD_HASH_~A" scenario-id)))
                           (unless fp-ok
                             (list (format nil "E3_DRIFT_FINGERPRINT_~A" scenario-id))))))
    (make-tui-drift-row
     :scenario-id     scenario-id
     :command-hash-ok cmd-ok
     :fingerprint-ok  fp-ok
     :fresh-p         fresh-p
     :baseline-fp     baseline-fp
     :current-fp      current-fp
     :drift-codes     codes
     :detail          (if fresh-p
                          (format nil "~A: fresh cmd_hash=~D fp=~D" scenario-id command-hash current-fp)
                          (format nil "~A: drift ~{~A~^,~}" scenario-id codes)))))

;;; ── Auditor ──────────────────────────────────────────────────────────────────

(defun audit-tui-replay-drift (current-batch baseline-batch)
  "Compare current T1-T6 fingerprint batch against baseline. Nil baseline = first-run (no drift)."
  (declare (type tui-fingerprint-batch current-batch)
           (type (or null tui-fingerprint-batch) baseline-batch)
           (optimize (safety 3)))
  (let* ((rows
           (mapcar (lambda (fp)
                     (let* ((sid (ttf-scenario-id fp))
                            (cur-fp (ttf-fingerprint fp))
                            (base-fp (if baseline-batch
                                         (let ((b (find sid (tfb-fingerprints baseline-batch)
                                                        :key #'ttf-scenario-id
                                                        :test #'string=)))
                                           (if b (ttf-fingerprint b) cur-fp))
                                         cur-fp)))
                       (build-tui-drift-row sid cur-fp base-fp (ttf-command-hash fp))))
                   (tfb-fingerprints current-batch)))
         (drift-count (count-if (lambda (r) (not (null (tdr-drift-codes r)))) rows))
         (stale-count (count-if (lambda (r) (not (tdr-fresh-p r))) rows))
         (pass-p      (zerop drift-count)))
    (make-tui-replay-drift-verdict
     :pass-p       pass-p
     :drift-count  drift-count
     :stale-count  stale-count
     :rows         rows
     :command-hash (tfb-command-hash current-batch)
     :timestamp    (get-universal-time)
     :detail       (format nil "pass=~A drift=~D stale=~D" pass-p drift-count stale-count))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %tdr->json (row)
  (declare (type tui-drift-row row))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"fresh\":~A,\"cmd_hash_ok\":~A,\"fp_ok\":~A,\"drift_codes\":["
            (tdr-scenario-id row)
            (if (tdr-fresh-p row) "true" "false")
            (if (tdr-command-hash-ok row) "true" "false")
            (if (tdr-fingerprint-ok row) "true" "false"))
    (loop for c in (tdr-drift-codes row)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" c)))
    (format out "],\"detail\":\"~A\"}" (tdr-detail row))))

(defun tui-replay-drift-verdict->json (verdict)
  (declare (type tui-replay-drift-verdict verdict))
  (with-output-to-string (out)
    (format out "{\"pass\":~A,\"drift_count\":~D,\"stale_count\":~D,\"command_hash\":~D,\"timestamp\":~D,\"rows\":["
            (if (trdv-pass-p verdict) "true" "false")
            (trdv-drift-count verdict)
            (trdv-stale-count verdict)
            (trdv-command-hash verdict)
            (trdv-timestamp verdict))
    (loop for row in (trdv-rows verdict)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%tdr->json row) out)))
    (format out "],\"detail\":\"~A\"}" (trdv-detail verdict))))
