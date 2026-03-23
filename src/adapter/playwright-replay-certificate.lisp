;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-replay-certificate.lisp — typed S1-S6 Playwright replay-certificate compiler
;;;   + deterministic artifact ledger exporter
;;; Bead: agent-orrery-0vdb
;;; Epic 4 hard policy: do NOT report complete without Playwright-backed S1-S6
;;;   screenshot+trace + deterministic command evidence.

(in-package #:orrery/adapter)

;;; ---------------------------------------------------------------------------
;;; ADTs

(defstruct (playwright-replay-cert-row (:conc-name prcr-))
  "Per-scenario S1-S6 row in a replay certificate."
  (scenario-id     ""  :type string)
  (screenshot-hash ""  :type string)
  (trace-hash      ""  :type string)
  (transcript-hash ""  :type string)
  (command-hash    0   :type integer)
  (complete-p      nil :type boolean))

(defstruct (playwright-replay-certificate (:conc-name prc-))
  "Deterministic replay certificate for a Playwright S1-S6 evidence run."
  (run-id              ""  :type string)
  (deterministic-command "" :type string)
  (command-fingerprint  0  :type integer)
  (command-canonical-p nil :type boolean)
  (scenario-count       0  :type integer)
  (complete-scenario-count 0 :type integer)
  (missing-scenarios   nil :type list)
  (rows                nil :type list)   ; list of playwright-replay-cert-row
  (ledger-hash         ""  :type string)
  (closure-ready-p     nil :type boolean)
  (timestamp            0  :type integer))

(defstruct (playwright-artifact-ledger-entry (:conc-name pale-))
  "One entry in the artifact ledger export."
  (scenario-id     ""  :type string)
  (screenshot-hash ""  :type string)
  (trace-hash      ""  :type string)
  (transcript-hash ""  :type string)
  (command-hash    0   :type integer)
  (present-p       nil :type boolean))

(defstruct (playwright-artifact-ledger (:conc-name pal-))
  "Machine-checkable artifact ledger export for eb0.4.5 lineage gates."
  (cert-run-id  "" :type string)
  (entries      nil :type list)           ; list of playwright-artifact-ledger-entry
  (scenario-count 0 :type integer)
  (complete-count 0 :type integer)
  (pass-p       nil :type boolean)
  (ledger-hash  ""  :type string)
  (exported-at   0  :type integer))

;;; ---------------------------------------------------------------------------
;;; Declarations

(declaim
 (ftype (function (playwright-replay-cert-row) (values string &optional))
        replay-cert-row->json)
 (ftype (function (list) (values string &optional))
        compute-replay-ledger-hash)
 (ftype (function (runner-evidence-manifest string) (values playwright-replay-certificate &optional))
        compile-playwright-replay-certificate)
 (ftype (function (playwright-replay-certificate) (values playwright-artifact-ledger &optional))
        export-playwright-artifact-ledger)
 (ftype (function (playwright-replay-certificate) (values string &optional))
        playwright-replay-certificate->json)
 (ftype (function (playwright-artifact-ledger) (values string &optional))
        playwright-artifact-ledger->json))

;;; ---------------------------------------------------------------------------
;;; Helpers

(defun replay-cert-row->json (row)
  (declare (type playwright-replay-cert-row row))
  (format nil "{\"scenario_id\":~S,\"screenshot_hash\":~S,\"trace_hash\":~S,~
\"transcript_hash\":~S,\"command_hash\":~D,\"complete\":~A}"
          (prcr-scenario-id row)
          (prcr-screenshot-hash row)
          (prcr-trace-hash row)
          (prcr-transcript-hash row)
          (prcr-command-hash row)
          (if (prcr-complete-p row) "true" "false")))

(defun compute-replay-ledger-hash (rows)
  "Compute a deterministic ledger hash over cert rows."
  (declare (type list rows))
  (let ((acc 0))
    (dolist (r rows)
      (setf acc (sxhash (format nil "~D|~A|~A|~A|~A|~:[0~;1~]"
                                acc
                                (prcr-scenario-id r)
                                (prcr-screenshot-hash r)
                                (prcr-trace-hash r)
                                (prcr-transcript-hash r)
                                (prcr-complete-p r)))))
    (write-to-string acc)))

;;; ---------------------------------------------------------------------------
;;; Core compiler

(defun compile-playwright-replay-certificate (manifest command)
  "Compile a typed S1-S6 replay certificate from a runner-evidence-manifest."
  (declare (type runner-evidence-manifest manifest)
           (type string command))
  (let* ((canonical-p (canonical-playwright-command-p command))
         (cmd-fp (sxhash command))
         (rows
           (mapcar
            (lambda (sid)
              (let* ((ss (find-scenario-artifact manifest sid :screenshot))
                     (tr (find-scenario-artifact manifest sid :trace))
                     (tx (find-scenario-artifact manifest sid :transcript))
                     (ss-hash (if (and ss (ea-present-p ss))
                                  (file-sha256 (ea-path ss)) ""))
                     (tr-hash (if (and tr (ea-present-p tr))
                                  (file-sha256 (ea-path tr)) ""))
                     (tx-hash (if (and tx (ea-present-p tx))
                                  (file-sha256 (ea-path tx)) ""))
                     (ok (and ss tr (not (string= ss-hash "")) (not (string= tr-hash "")))))
                (make-playwright-replay-cert-row
                 :scenario-id sid
                 :screenshot-hash ss-hash
                 :trace-hash tr-hash
                 :transcript-hash tx-hash
                 :command-hash cmd-fp
                 :complete-p ok)))
            *default-web-scenarios*))
         (missing (loop for r in rows
                        unless (prcr-complete-p r)
                          collect (prcr-scenario-id r)))
         (complete-count (count-if #'prcr-complete-p rows))
         (ledger-hash (compute-replay-ledger-hash rows))
         (closure-p (and canonical-p (null missing))))
    (make-playwright-replay-certificate
     :run-id (format nil "pw-replay-cert-~D" (get-universal-time))
     :deterministic-command command
     :command-fingerprint cmd-fp
     :command-canonical-p canonical-p
     :scenario-count (length *default-web-scenarios*)
     :complete-scenario-count complete-count
     :missing-scenarios missing
     :rows rows
     :ledger-hash ledger-hash
     :closure-ready-p closure-p
     :timestamp (get-universal-time))))

;;; ---------------------------------------------------------------------------
;;; Artifact ledger exporter

(defun export-playwright-artifact-ledger (cert)
  "Export a machine-checkable artifact ledger from a replay certificate."
  (declare (type playwright-replay-certificate cert))
  (let* ((entries
           (mapcar
            (lambda (row)
              (make-playwright-artifact-ledger-entry
               :scenario-id (prcr-scenario-id row)
               :screenshot-hash (prcr-screenshot-hash row)
               :trace-hash (prcr-trace-hash row)
               :transcript-hash (prcr-transcript-hash row)
               :command-hash (prcr-command-hash row)
               :present-p (prcr-complete-p row)))
            (prc-rows cert)))
         (complete-count (count-if #'pale-present-p entries)))
    (make-playwright-artifact-ledger
     :cert-run-id (prc-run-id cert)
     :entries entries
     :scenario-count (prc-scenario-count cert)
     :complete-count complete-count
     :pass-p (prc-closure-ready-p cert)
     :ledger-hash (prc-ledger-hash cert)
     :exported-at (get-universal-time))))

;;; ---------------------------------------------------------------------------
;;; JSON serializers

(defun playwright-replay-certificate->json (cert)
  (declare (type playwright-replay-certificate cert))
  (format nil "{\"run_id\":~S,\"deterministic_command\":~S,~
\"command_fingerprint\":~D,\"command_canonical\":~A,~
\"scenario_count\":~D,\"complete_scenario_count\":~D,~
\"missing_scenarios\":[~{~S~^,~}],\"ledger_hash\":~S,~
\"closure_ready\":~A,\"timestamp\":~D,~
\"rows\":[~{~A~^,~}]}"
          (prc-run-id cert)
          (prc-deterministic-command cert)
          (prc-command-fingerprint cert)
          (if (prc-command-canonical-p cert) "true" "false")
          (prc-scenario-count cert)
          (prc-complete-scenario-count cert)
          (prc-missing-scenarios cert)
          (prc-ledger-hash cert)
          (if (prc-closure-ready-p cert) "true" "false")
          (prc-timestamp cert)
          (mapcar #'replay-cert-row->json (prc-rows cert))))

(defun playwright-artifact-ledger->json (ledger)
  (declare (type playwright-artifact-ledger ledger))
  (format nil "{\"cert_run_id\":~S,\"scenario_count\":~D,~
\"complete_count\":~D,\"pass\":~A,\"ledger_hash\":~S,~
\"exported_at\":~D,\"entries\":[~{~A~^,~}]}"
          (pal-cert-run-id ledger)
          (pal-scenario-count ledger)
          (pal-complete-count ledger)
          (if (pal-pass-p ledger) "true" "false")
          (pal-ledger-hash ledger)
          (pal-exported-at ledger)
          (mapcar (lambda (e)
                    (format nil "{\"scenario_id\":~S,\"screenshot_hash\":~S,~
\"trace_hash\":~S,\"transcript_hash\":~S,~
\"command_hash\":~D,\"present\":~A}"
                            (pale-scenario-id e)
                            (pale-screenshot-hash e)
                            (pale-trace-hash e)
                            (pale-transcript-hash e)
                            (pale-command-hash e)
                            (if (pale-present-p e) "true" "false")))
                  (pal-entries ledger))))
