;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; missing-boundary-declarations.lisp — Fills missing ftype/boundary declarations
;;; and provides stubs for exported symbols not yet implemented elsewhere.
;;;
;;; This file MUST be loaded AFTER all other adapter files so all types are in scope.

(in-package #:orrery/adapter)

;;; ─── compute-seq-id (alias for internal computev-seq-id) ────────────────────

(declaim (ftype (function (source-tag event-kind fixnum fixnum) (values fixnum &optional))
                compute-seq-id))
(defun compute-seq-id (source event-k timestamp payload-hash)
  "Public alias for computev-seq-id. Produces a deterministic seq-id integer."
  (declare (type source-tag source)
           (type event-kind event-k)
           (type fixnum timestamp payload-hash))
  (computev-seq-id source event-k timestamp payload-hash))

;;; ─── e4ed-transcript-fingerprints (alias for e4ed-transcript-attestations) ──

(declaim (ftype (function (epic4-evidence-dossier) (values list &optional))
                e4ed-transcript-fingerprints))
(defun e4ed-transcript-fingerprints (dossier)
  "Public alias for e4ed-transcript-attestations (alist of scenario-id . hash)."
  (declare (type epic4-evidence-dossier dossier))
  (e4ed-transcript-attestations dossier))

;;; ─── scenario-ledger-entry / scenario-ledger / scenario-continuity-verdict ──
;;; These are generic cross-framework ledger types exported from the adapter package.

(defstruct (scenario-ledger-entry
             (:constructor make-scenario-ledger-entry
                 (&key scenario-id command command-fingerprint
                       artifact-paths artifact-hashes
                       transcript-hash attested-p))
             (:conc-name sle-))
  "A single scenario's attestation entry in a cross-framework ledger."
  (scenario-id "" :type string)
  (command "" :type string)
  (command-fingerprint 0 :type integer)
  (artifact-paths '() :type list)
  (artifact-hashes '() :type list)
  (transcript-hash "" :type string)
  (attested-p nil :type boolean))

(defstruct (scenario-ledger
             (:constructor make-scenario-ledger (&key run-id entries timestamp))
             (:conc-name sl-))
  "A cross-framework scenario run ledger."
  (run-id "" :type string)
  (entries '() :type list)
  (timestamp 0 :type integer))

(defstruct (scenario-continuity-verdict
             (:constructor make-scenario-continuity-verdict
                 (&key pass-p missing-scenarios mismatched-scenarios detail))
             (:conc-name scv-))
  "Verdict from comparing two scenario ledger runs."
  (pass-p nil :type boolean)
  (missing-scenarios '() :type list)
  (mismatched-scenarios '() :type list)
  (detail "" :type string))

(declaim
 (ftype (function (string) (values integer &optional)) simple-fingerprint)
 (ftype (function (string (or null list)) (values list &optional)) collect-scenario-artifacts)
 (ftype (function (string string list) (values scenario-ledger &optional)) build-tui-scenario-ledger)
 (ftype (function ((or null scenario-ledger) scenario-ledger)
                  (values scenario-continuity-verdict &optional))
        compare-ledger-runs)
 (ftype (function (scenario-continuity-verdict) (values string &optional))
        scenario-continuity-verdict->json))

(defun simple-fingerprint (s)
  "Compute a simple integer fingerprint for string S (djb2-style)."
  (declare (type string s))
  (let ((h 5381))
    (dotimes (i (length s) (logand h most-positive-fixnum))
      (setf h (logand (+ (ash h 5) h (char-code (char s i)))
                      most-positive-fixnum)))))

(defun collect-scenario-artifacts (artifact-root scenario-ids)
  "Return alist of (scenario-id . paths) for files found under ARTIFACT-ROOT."
  (declare (type string artifact-root)
           (type (or null list) scenario-ids))
  (when (and artifact-root (probe-file artifact-root))
    (let ((ids (or scenario-ids *default-tui-scenarios*)))
      (mapcar (lambda (sid)
                (cons sid
                      (directory
                       (make-pathname :defaults (pathname artifact-root)
                                     :name :wild
                                     :type :wild))))
              ids))))

(defun build-tui-scenario-ledger (run-id command scenario-ids)
  "Build a scenario-ledger from a command run over SCENARIO-IDS."
  (declare (type string run-id command)
           (type list scenario-ids))
  (let ((entries (mapcar (lambda (sid)
                           (make-scenario-ledger-entry
                            :scenario-id sid
                            :command command
                            :command-fingerprint (simple-fingerprint command)
                            :artifact-paths '()
                            :artifact-hashes '()
                            :transcript-hash ""
                            :attested-p nil))
                         scenario-ids)))
    (make-scenario-ledger
     :run-id run-id
     :entries entries
     :timestamp (get-universal-time))))

(defun compare-ledger-runs (prior-ledger current-ledger)
  "Compare PRIOR-LEDGER to CURRENT-LEDGER, returning a continuity verdict."
  (declare (type (or null scenario-ledger) prior-ledger)
           (type scenario-ledger current-ledger))
  (if (null prior-ledger)
      (make-scenario-continuity-verdict
       :pass-p t
       :missing-scenarios '()
       :mismatched-scenarios '()
       :detail "baseline-established")
      (let ((prior-ids (mapcar #'sle-scenario-id (sl-entries prior-ledger)))
            (current-ids (mapcar #'sle-scenario-id (sl-entries current-ledger)))
            (mismatched '()))
        (dolist (entry (sl-entries current-ledger))
          (let ((prior-entry (find (sle-scenario-id entry)
                                   (sl-entries prior-ledger)
                                   :key #'sle-scenario-id :test #'string=)))
            (when (and prior-entry
                       (not (= (sle-command-fingerprint entry)
                               (sle-command-fingerprint prior-entry))))
              (push (sle-scenario-id entry) mismatched))))
        (let* ((missing (set-difference prior-ids current-ids :test #'string=))
               (pass-p (and (null missing) (null mismatched))))
          (make-scenario-continuity-verdict
           :pass-p pass-p
           :missing-scenarios missing
           :mismatched-scenarios mismatched
           :detail (if pass-p "continuity-ok" "continuity-mismatch"))))))

(defun scenario-continuity-verdict->json (v)
  "Serialize a scenario-continuity-verdict to a JSON string."
  (declare (type scenario-continuity-verdict v))
  (with-output-to-string (s)
    (format s "{\"pass\":~A,\"missing\":[~{~S~^,~}],\"mismatched\":[~{~S~^,~}],\"detail\":~S}"
            (if (scv-pass-p v) "true" "false")
            (scv-missing-scenarios v)
            (scv-mismatched-scenarios v)
            (scv-detail v))))

;;; ─── ftype declarations for existing functions missing declarations ──────────

(declaim
 ;; resilience-suite.lisp
 (ftype (function (t keyword function)
                  (values t keyword boolean t integer &optional))
        attempt-with-recovery)
 (ftype (function (t symbol function) (values fault-injecting-adapter &optional)) make-fault-injecting-adapter)
 ;; runtime-transport.lisp
 (ftype (function (list) (values t &optional)) make-fixture-transport)
 (ftype (function () (values t &optional)) make-dexador-transport)
 ;; performance-soak.lisp
 (ftype (function (t) (values string &optional)) concurrent-stress-result->json)
 ;; closure-preflight-aggregator.lisp
 (ftype (function (t t) (values t &optional)) aggregate-from-raw-verdicts)
 (ftype (function (string string string string) (values t &optional))
        run-closure-preflight-aggregator)
 ;; epic4-closure-attestation-exporter.lisp
 (ftype (function (string string) (values t &optional))
        run-epic4-closure-attestation-exporter)
 ;; epic4-evidence-dossier-compiler.lisp
 (ftype (function (string string) (values t &optional))
        run-epic4-evidence-dossier-compiler)
 ;; unified-closure-gate.lisp
 (ftype (function (string string string string string) (values t &optional))
        run-unified-closure-gate-compiler)
 ;; playwright-provenance-timeline-indexer.lisp
 (ftype (function (string (integer 0) string string &key (:timestamp (integer 0)) (:drift-rationale t))
                  (values t &optional))
        build-provenance-timeline-entry)
 (ftype (function (string list) (values t &optional))
        build-scenario-provenance-timeline)
 (ftype (function (string list) (values t &optional))
        build-playwright-provenance-index)
 ;; observability-trace-contract.lisp
 (ftype (function () (values t &optional)) make-core-obligations)
 (ftype (function () (values t &optional)) make-tui-contract)
 (ftype (function () (values t &optional)) make-web-contract)
 (ftype (function () (values t &optional)) make-mcclim-contract))
