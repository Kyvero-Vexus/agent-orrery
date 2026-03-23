;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-provenance-auditor.lisp — typed S1-S6 trace/screenshot provenance auditor + drift alarms
;;; Bead: agent-orrery-kz5

(in-package #:orrery/adapter)

;;; ── Provenance record ────────────────────────────────────────────────────────

(defstruct (playwright-provenance-record (:conc-name ppr2-))
  "Provenance record for one S1-S6 screenshot+trace pair."
  (scenario-id       ""    :type string)
  (screenshot-digest ""    :type string)
  (trace-digest      ""    :type string)
  (command-hash      0     :type integer)
  (lineage-ok-p      nil   :type boolean)
  (alarm-codes       nil   :type list)
  (detail            ""    :type string))

;;; ── Provenance audit result ──────────────────────────────────────────────────

(defstruct (playwright-provenance-audit (:conc-name ppa-))
  "Aggregate S1-S6 provenance audit with drift alarms."
  (pass-p        nil   :type boolean)
  (alarm-count   0     :type (integer 0))
  (records       nil   :type list)
  (command-hash  0     :type integer)
  (timestamp     0     :type integer)
  (detail        ""    :type string))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string string string string string)
                  (values playwright-provenance-record &optional))
        build-playwright-provenance-record)
 (ftype (function (string string) (values playwright-provenance-audit &optional))
        run-playwright-provenance-audit)
 (ftype (function (playwright-provenance-audit) (values string &optional))
        playwright-provenance-audit->json))

;;; ── Builder ──────────────────────────────────────────────────────────────────

(defun build-playwright-provenance-record (scenario-id artifact-root screenshot trace command)
  "Build a provenance record checking artifact presence and command lineage."
  (declare (type string scenario-id artifact-root screenshot trace command)
           (optimize (safety 3)))
  (let* ((cmd-hash    (command-fingerprint command))
         (canon-hash  *playwright-canonical-command-hash*)
         (cmd-ok      (= cmd-hash canon-hash))
         (scr-path    (merge-pathnames screenshot (pathname artifact-root)))
         (trc-path    (merge-pathnames trace (pathname artifact-root)))
         (scr-ok      (not (null (probe-file scr-path))))
         (trc-ok      (not (null (probe-file trc-path))))
         (scr-digest  (if scr-ok (%hash-text-file (namestring scr-path)) ""))
         (trc-digest  (if trc-ok (%hash-text-file (namestring trc-path)) ""))
         (lineage-ok  (and cmd-ok scr-ok trc-ok))
         (alarms      (append
                       (unless cmd-ok  (list (format nil "E4_PROV_CMD_DRIFT_~A" scenario-id)))
                       (unless scr-ok  (list (format nil "E4_PROV_SCR_MISSING_~A" scenario-id)))
                       (unless trc-ok  (list (format nil "E4_PROV_TRC_MISSING_~A" scenario-id))))))
    (make-playwright-provenance-record
     :scenario-id       scenario-id
     :screenshot-digest scr-digest
     :trace-digest      trc-digest
     :command-hash      cmd-hash
     :lineage-ok-p      lineage-ok
     :alarm-codes       alarms
     :detail            (if lineage-ok
                            (format nil "~A: lineage ok" scenario-id)
                            (format nil "~A: alarms ~{~A~^,~}" scenario-id alarms)))))

(defun run-playwright-provenance-audit (artifact-root command)
  "Run S1-S6 provenance audit: validate screenshot+trace lineage + command fingerprints."
  (declare (type string artifact-root command)
           (optimize (safety 3)))
  (let* ((manifest (compile-playwright-evidence-manifest artifact-root command))
         (records
           (mapcar (lambda (sid)
                     (let ((scr (find-web-scenario-artifact-path manifest sid :screenshot))
                           (trc (find-web-scenario-artifact-path manifest sid :trace)))
                       (build-playwright-provenance-record
                        sid artifact-root
                        (if (plusp (length scr)) scr "missing-screenshot")
                        (if (plusp (length trc)) trc "missing-trace")
                        command)))
                   *playwright-required-scenarios*))
         (alarm-count (count-if (lambda (r) (not (null (ppr2-alarm-codes r)))) records))
         (pass-p      (zerop alarm-count)))
    (make-playwright-provenance-audit
     :pass-p       pass-p
     :alarm-count  alarm-count
     :records      records
     :command-hash (command-fingerprint command)
     :timestamp    (get-universal-time)
     :detail       (format nil "pass=~A alarms=~D" pass-p alarm-count))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %ppr2->json (r)
  (declare (type playwright-provenance-record r))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"lineage_ok\":~A,\"command_hash\":~D,\"screenshot_digest\":\"~A\",\"trace_digest\":\"~A\",\"alarm_codes\":["
            (ppr2-scenario-id r)
            (if (ppr2-lineage-ok-p r) "true" "false")
            (ppr2-command-hash r)
            (ppr2-screenshot-digest r)
            (ppr2-trace-digest r))
    (loop for c in (ppr2-alarm-codes r)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" c)))
    (format out "]}")))

(defun playwright-provenance-audit->json (audit)
  (declare (type playwright-provenance-audit audit))
  (with-output-to-string (out)
    (format out "{\"pass\":~A,\"alarm_count\":~D,\"command_hash\":~D,\"timestamp\":~D,\"records\":["
            (if (ppa-pass-p audit) "true" "false")
            (ppa-alarm-count audit)
            (ppa-command-hash audit)
            (ppa-timestamp audit))
    (loop for r in (ppa-records audit)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%ppr2->json r) out)))
    (format out "],\"detail\":\"~A\"}" (ppa-detail audit))))
