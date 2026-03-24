;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-command-fingerprint-baseline-ledger.lisp
;;;   Immutable baseline-ledger for T1-T6 deterministic command fingerprints +
;;;   transcript digests.  Produces baseline version IDs, drift-delta records,
;;;   and machine-checkable JSON verdicts consumed by Epic 3 closure gates.
;;;
;;; Bead: agent-orrery-0ko9
;;;
;;; Deterministic command: cd e2e-tui && ./run-tui-e2e-t1-t6.sh
;;; Architecture: /home/slime/projects/emacsen-design-docs/agent-orrery/
;;;               epic-3-command-fingerprint-baseline-ledger-0ko9.md

(in-package #:orrery/adapter)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: baseline-snapshot
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (baseline-snapshot (:conc-name bsnap-))
  "Immutable snapshot of command-fingerprint + per-scenario transcript digests."
  (version-id         ""  :type string)  ; content-addressed hex id
  (command            ""  :type string)
  (command-fingerprint "" :type string)  ; sxhash hex of command
  (scenario-digests   nil :type list)    ; alist: (scenario-keyword . digest-string)
  (captured-at        0   :type integer)
  (canonical-p        nil :type boolean))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: baseline-ledger
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (baseline-ledger (:conc-name bldr-))
  "Ordered, append-only list of baseline snapshots."
  (snapshots          nil :type list)    ; list of baseline-snapshot, oldest first
  (latest-version-id  ""  :type string)
  (snapshot-count     0   :type fixnum))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: drift-delta
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (drift-delta (:conc-name ddelta-))
  "Per-scenario drift record comparing baseline to current snapshot."
  (scenario-id        :T1 :type symbol) ; one of :T1 .. :T6
  (status             :stable :type (member :stable :drifted :missing))
  (old-digest         ""  :type string)
  (new-digest         ""  :type string))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: baseline-drift-report
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (baseline-drift-report (:conc-name bdr-))
  "Full cross-scenario drift report with machine-checkable closure verdict."
  (baseline-version   ""  :type string)
  (current-version    ""  :type string)
  (verdict            :rejected :type (member :clean :drifted :rejected))
  (deltas             nil :type list)    ; list of drift-delta
  (drifted-count      0   :type fixnum)
  (timestamp          0   :type integer))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Declaims
;;; ─────────────────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string) (values string &optional))
        fingerprint-string)
 (ftype (function (list string) (values string &optional))
        compute-baseline-version-id)
 (ftype (function (t1-t6-replay-journal) (values baseline-snapshot &optional))
        capture-baseline-snapshot)
 (ftype (function (baseline-ledger baseline-snapshot) (values baseline-ledger &optional))
        append-snapshot)
 (ftype (function (baseline-snapshot baseline-snapshot) (values list &optional))
        compute-drift-deltas)
 (ftype (function (baseline-snapshot baseline-snapshot) (values baseline-drift-report &optional))
        build-baseline-drift-report)
 (ftype (function (baseline-drift-report) (values (member :clean :drifted :rejected) &optional))
        verdict-from-baseline-drift-report)
 (ftype (function (baseline-ledger) (values string &optional))
        baseline-ledger->json)
 (ftype (function (baseline-drift-report) (values string &optional))
        baseline-drift-report->json))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Constants
;;; ─────────────────────────────────────────────────────────────────────────────

(defparameter *t1-t6-scenarios*
  '(:T1 :T2 :T3 :T4 :T5 :T6)
  "Ordered scenario identifiers for T1-T6 baseline ledger.")

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun fingerprint-string (s)
  "Return sxhash of S as an uppercase hex string."
  (declare (type string s))
  (format nil "~8,'0X" (sxhash s)))

(defun compute-baseline-version-id (scenario-digests command-fingerprint)
  "Derive a content-addressed version ID from COMMAND-FINGERPRINT and
SCENARIO-DIGESTS (alist in canonical T1..T6 order)."
  (declare (type list scenario-digests)
           (type string command-fingerprint))
  (let* ((ordered (mapcar (lambda (k)
                            (or (cdr (assoc k scenario-digests)) ""))
                          *t1-t6-scenarios*))
         (blob (format nil "~A:~{~A~^:~}" command-fingerprint ordered)))
    (fingerprint-string blob)))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; capture-baseline-snapshot
;;; ─────────────────────────────────────────────────────────────────────────────

(defun capture-baseline-snapshot (journal)
  "Create an immutable baseline-snapshot from a T1-T6-REPLAY-JOURNAL.
Fail-closed: if the journal command is not canonical the snapshot is marked
non-canonical and will yield a :REJECTED verdict downstream."
  (declare (type t1-t6-replay-journal journal))
  (let* ((cmd         (journal-deterministic-command journal))
         (canon-p     (canonical-command-p cmd))
         (cmd-fp      (fingerprint-string cmd))
         (digests     (mapcar (lambda (row)
                                (let* ((sid (jrow-scenario-id row))
                                       (td  (jrow-transcript-digest row))
                                       (dig (if td (rtd-digest td) "")))
                                  (cons sid dig)))
                              (journal-rows journal)))
         ;; pad any missing scenarios
         (full-digests (mapcar (lambda (k)
                                 (cons k (or (cdr (assoc k digests)) "")))
                               *t1-t6-scenarios*))
         (ver-id (compute-baseline-version-id full-digests cmd-fp)))
    (make-baseline-snapshot
     :version-id         ver-id
     :command            cmd
     :command-fingerprint cmd-fp
     :scenario-digests   full-digests
     :captured-at        (get-universal-time)
     :canonical-p        canon-p)))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; append-snapshot — pure transform
;;; ─────────────────────────────────────────────────────────────────────────────

(defun append-snapshot (ledger snapshot)
  "Return a new BASELINE-LEDGER with SNAPSHOT appended.  Pure — does not modify
the original ledger."
  (declare (type baseline-ledger ledger)
           (type baseline-snapshot snapshot))
  (make-baseline-ledger
   :snapshots         (append (bldr-snapshots ledger) (list snapshot))
   :latest-version-id (bsnap-version-id snapshot)
   :snapshot-count    (1+ (bldr-snapshot-count ledger))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; compute-drift-deltas
;;; ─────────────────────────────────────────────────────────────────────────────

(defun compute-drift-deltas (baseline current)
  "Return a list of DRIFT-DELTAs comparing BASELINE snapshot to CURRENT snapshot,
in T1..T6 order."
  (declare (type baseline-snapshot baseline)
           (type baseline-snapshot current))
  (mapcar (lambda (sid)
            (let* ((old (or (cdr (assoc sid (bsnap-scenario-digests baseline))) ""))
                   (new (or (cdr (assoc sid (bsnap-scenario-digests current)))  ""))
                   (status (cond ((and (string= old "") (string= new "")) :missing)
                                 ((string= old new)                       :stable)
                                 (t                                       :drifted))))
              (make-drift-delta
               :scenario-id sid
               :status      status
               :old-digest  old
               :new-digest  new)))
          *t1-t6-scenarios*))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; build-baseline-drift-report
;;; ─────────────────────────────────────────────────────────────────────────────

(defun build-baseline-drift-report (baseline current)
  "Build a DRIFT-REPORT comparing BASELINE to CURRENT.
Verdict is :REJECTED if either snapshot is non-canonical, :CLEAN if all deltas
are :STABLE, :DRIFTED otherwise."
  (declare (type baseline-snapshot baseline)
           (type baseline-snapshot current))
  (let* ((deltas     (compute-drift-deltas baseline current))
         (drifted-n  (count :drifted deltas :key #'ddelta-status))
         (verdict    (cond ((not (and (bsnap-canonical-p baseline)
                                     (bsnap-canonical-p current)))
                            :rejected)
                           ((zerop drifted-n) :clean)
                           (t                 :drifted))))
    (make-baseline-drift-report
     :baseline-version (bsnap-version-id baseline)
     :current-version  (bsnap-version-id current)
     :verdict          verdict
     :deltas           deltas
     :drifted-count    drifted-n
     :timestamp        (get-universal-time))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; verdict-from-baseline-drift-report
;;; ─────────────────────────────────────────────────────────────────────────────

(defun verdict-from-baseline-drift-report (report)
  "Extract the :CLEAN/:DRIFTED/:REJECTED verdict from REPORT."
  (declare (type baseline-drift-report report))
  (bdr-verdict report))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; JSON serialisation
;;; ─────────────────────────────────────────────────────────────────────────────

(defun drift-delta->json-fragment (d)
  "Serialize a single DRIFT-DELTA to a JSON object string."
  (declare (type drift-delta d))
  (format nil "{\"scenario\":~S,\"status\":~S,\"old_digest\":~S,\"new_digest\":~S}"
          (string-downcase (symbol-name (ddelta-scenario-id d)))
          (string-downcase (symbol-name (ddelta-status d)))
          (ddelta-old-digest d)
          (ddelta-new-digest d)))

(defun baseline-drift-report->json (report)
  "Serialize DRIFT-REPORT to a JSON string."
  (declare (type baseline-drift-report report))
  (let ((delta-jsons (mapcar #'drift-delta->json-fragment (bdr-deltas report))))
    (format nil
            "{\"baseline_version\":~S,\"current_version\":~S,\"verdict\":~S,\"drifted_count\":~D,\"deltas\":[~{~A~^,~}],\"timestamp\":~D}"
            (bdr-baseline-version report)
            (bdr-current-version  report)
            (string-downcase (symbol-name (bdr-verdict report)))
            (bdr-drifted-count report)
            delta-jsons
            (bdr-timestamp report))))

(defun baseline-snapshot->json-fragment (snap)
  "Serialize a single BASELINE-SNAPSHOT to a JSON object string."
  (declare (type baseline-snapshot snap))
  (let ((digest-pairs
          (mapcar (lambda (pair)
                    (format nil "~S:~S"
                            (string-downcase (symbol-name (car pair)))
                            (cdr pair)))
                  (bsnap-scenario-digests snap))))
    (format nil
            "{\"version_id\":~S,\"command\":~S,\"command_fingerprint\":~S,\"canonical\":~A,\"captured_at\":~D,\"scenario_digests\":{~{~A~^,~}}}"
            (bsnap-version-id snap)
            (bsnap-command snap)
            (bsnap-command-fingerprint snap)
            (if (bsnap-canonical-p snap) "true" "false")
            (bsnap-captured-at snap)
            digest-pairs)))

(defun baseline-ledger->json (ledger)
  "Serialize BASELINE-LEDGER to a JSON string."
  (declare (type baseline-ledger ledger))
  (let ((snap-jsons (mapcar #'baseline-snapshot->json-fragment
                            (bldr-snapshots ledger))))
    (format nil
            "{\"snapshot_count\":~D,\"latest_version_id\":~S,\"snapshots\":[~{~A~^,~}]}"
            (bldr-snapshot-count ledger)
            (bldr-latest-version-id ledger)
            snap-jsons)))
