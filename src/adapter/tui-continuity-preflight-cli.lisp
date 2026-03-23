;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-continuity-preflight-cli.lisp — T1-T6 continuity preflight CLI + JSON verdict
;;; Bead: agent-orrery-6oh

(in-package #:orrery/adapter)

;;; ── Continuity verdict ───────────────────────────────────────────────────────

(defstruct (tui-continuity-verdict (:conc-name tcv-))
  "Machine-checkable continuity preflight verdict for T1-T6 scenarios."
  (pass-p            nil   :type boolean)
  (command-ok-p      nil   :type boolean)
  (missing-scenarios nil   :type list)
  (mismatch-scenarios nil  :type list)
  (scenario-count    0     :type (integer 0))
  (complete-count    0     :type (integer 0))
  (command           ""    :type string)
  (command-hash      0     :type integer)
  (detail            ""    :type string)
  (timestamp         0     :type integer))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string string) (values tui-continuity-verdict &optional))
        run-tui-continuity-preflight)
 (ftype (function (tui-continuity-verdict) (values string &optional))
        tui-continuity-verdict->json))

;;; ── Preflight runner ─────────────────────────────────────────────────────────

(defun run-tui-continuity-preflight (artifact-root command)
  "Run T1-T6 continuity preflight: check command matches canonical, verify artifact presence.
Returns machine-checkable TUI-CONTINUITY-VERDICT."
  (declare (type string artifact-root command)
           (optimize (safety 3)))
  (let* ((canonical-cmd  *mcp-tui-deterministic-command*)
         (command-ok     (string= command canonical-cmd))
         (cmd-hash       (command-fingerprint command))
         (missing        nil)
         (complete-count 0))
    ;; Check per-scenario artifact presence (asciicast as proxy)
    (dolist (sid *mcp-tui-required-scenarios*)
      (let* ((asciicast-path (format nil "~A~A.cast" artifact-root sid))
             (present-p (probe-file asciicast-path)))
        (if present-p
            (incf complete-count)
            (push sid missing))))
    (let* ((missing-rev  (nreverse missing))
           (all-present  (null missing-rev))
           (pass-p       (and command-ok all-present))
           (detail       (format nil "command_ok=~A missing=~{~A~^,~} complete=~D/~D"
                                 (if command-ok "true" "false")
                                 missing-rev
                                 complete-count
                                 (length *mcp-tui-required-scenarios*))))
      (make-tui-continuity-verdict
       :pass-p            pass-p
       :command-ok-p      command-ok
       :missing-scenarios missing-rev
       :mismatch-scenarios nil
       :scenario-count    (length *mcp-tui-required-scenarios*)
       :complete-count    complete-count
       :command           command
       :command-hash      cmd-hash
       :detail            detail
       :timestamp         (get-universal-time)))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun tui-continuity-verdict->json (verdict)
  "Serialise TUI-CONTINUITY-VERDICT to machine-readable JSON."
  (declare (type tui-continuity-verdict verdict))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"command_ok\":~A,\"command_hash\":~D,\"scenario_count\":~D,\"complete_count\":~D,\"missing_count\":~D,\"missing_scenarios\":["
            (if (tcv-pass-p verdict)       "true" "false")
            (if (tcv-command-ok-p verdict) "true" "false")
            (tcv-command-hash verdict)
            (tcv-scenario-count verdict)
            (tcv-complete-count verdict)
            (length (tcv-missing-scenarios verdict)))
    (loop for sid in (tcv-missing-scenarios verdict)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" sid)))
    (format out "],\"detail\":\"~A\",\"timestamp\":~D}"
            (tcv-detail verdict)
            (tcv-timestamp verdict))))
