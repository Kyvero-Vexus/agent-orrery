;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-packager.lisp — typed S1-S6 evidence packager + deterministic replay index
;;; Bead: agent-orrery-7r2

(in-package #:orrery/adapter)

;;; ── Evidence bundle entry ────────────────────────────────────────────────────

(defstruct (playwright-bundle-entry (:conc-name pbe-))
  "One scenario's worth of immutable evidence in a bundle."
  (scenario-id      ""    :type string)
  (screenshot-path  ""    :type string)
  (trace-path       ""    :type string)
  (screenshot-hash  ""    :type string)
  (trace-hash       ""    :type string)
  (replay-command   ""    :type string)
  (command-hash     0     :type integer)
  (complete-p       nil   :type boolean))

;;; ── Evidence bundle ──────────────────────────────────────────────────────────

(defstruct (playwright-evidence-bundle (:conc-name peb-))
  "Immutable S1-S6 evidence bundle with deterministic replay index."
  (bundle-id       ""    :type string)
  (command         ""    :type string)
  (command-hash    0     :type integer)
  (entries         nil   :type list)    ; list of playwright-bundle-entry
  (complete-count  0     :type (integer 0))
  (missing-count   0     :type (integer 0))
  (ready-p         nil   :type boolean)
  (timestamp       0     :type integer))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string string) (values playwright-evidence-bundle &optional))
        compile-playwright-evidence-bundle)
 (ftype (function (playwright-evidence-bundle) (values string &optional))
        playwright-evidence-bundle->json))

;;; ── Builder ──────────────────────────────────────────────────────────────────

(defun %make-bundle-entry (manifest scenario-id command)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id command))
  (let* ((scr   (find-web-scenario-artifact-path manifest scenario-id :screenshot))
         (trc   (find-web-scenario-artifact-path manifest scenario-id :trace))
         (scr-ok (plusp (length scr)))
         (trc-ok (plusp (length trc)))
         (complete (and scr-ok trc-ok))
         (replay  (format nil "WEB_EVIDENCE_COMMAND='~A' SCENARIO=~A ~A"
                          command scenario-id command)))
    (make-playwright-bundle-entry
     :scenario-id      scenario-id
     :screenshot-path  scr
     :trace-path       trc
     :screenshot-hash  (if scr-ok (%hash-text-file scr) "")
     :trace-hash       (if trc-ok (%hash-text-file trc) "")
     :replay-command   replay
     :command-hash     (command-fingerprint command)
     :complete-p       complete)))

(defun compile-playwright-evidence-bundle (artifact-root command)
  "Ingest S1-S6 artifacts and emit immutable evidence bundle with replay index.
Fails readiness when any scenario evidence is missing."
  (declare (type string artifact-root command)
           (optimize (safety 3)))
  (let* ((manifest (compile-playwright-evidence-manifest artifact-root command))
         (entries  (mapcar (lambda (sid) (%make-bundle-entry manifest sid command))
                           *playwright-required-scenarios*))
         (complete (count-if #'pbe-complete-p entries))
         (missing  (- (length entries) complete))
         (ready    (zerop missing)))
    (make-playwright-evidence-bundle
     :bundle-id       (format nil "peb-~D" (get-universal-time))
     :command         command
     :command-hash    (command-fingerprint command)
     :entries         entries
     :complete-count  complete
     :missing-count   missing
     :ready-p         ready
     :timestamp       (get-universal-time))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %pbe->json (e)
  (declare (type playwright-bundle-entry e))
  (format nil "{\"scenario\":\"~A\",\"complete\":~A,\"command_hash\":~D,\"screenshot_hash\":\"~A\",\"trace_hash\":\"~A\",\"replay_command\":\"~A\"}"
          (pbe-scenario-id e)
          (if (pbe-complete-p e) "true" "false")
          (pbe-command-hash e)
          (pbe-screenshot-hash e)
          (pbe-trace-hash e)
          (pbe-replay-command e)))

(defun playwright-evidence-bundle->json (bundle)
  (declare (type playwright-evidence-bundle bundle))
  (with-output-to-string (out)
    (format out "{\"bundle_id\":\"~A\",\"command_hash\":~D,\"ready\":~A,\"complete_count\":~D,\"missing_count\":~D,\"timestamp\":~D,\"entries\":["
            (peb-bundle-id bundle)
            (peb-command-hash bundle)
            (if (peb-ready-p bundle) "true" "false")
            (peb-complete-count bundle)
            (peb-missing-count bundle)
            (peb-timestamp bundle))
    (loop for e in (peb-entries bundle)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%pbe->json e) out)))
    (write-string "]}" out)))
