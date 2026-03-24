;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-provenance-timeline-indexer.lisp
;;;   Typed CL provenance timeline indexer for Playwright S1-S6 evidence
;;;   evolution across reruns for agent-orrery-eb0.4.5+.
;;;   Bead: agent-orrery-jyhv
;;;
;;; Records deterministic run-command fingerprint lineage, screenshot+trace
;;; digest history, and timestamped drift rationale entries consumed by
;;; closure diagnostics.
;;;
;;; All transforms are pure / side-effect-free unless noted.
;;; Strict SBCL declarations throughout.

(in-package #:orrery/adapter)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADTs
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (provenance-timeline-entry (:conc-name pte-))
  "One timestamped evidence snapshot in a scenario's provenance timeline."
  (scenario-id      ""  :type string)
  (rerun-index      0   :type (integer 0))
  (timestamp        0   :type integer)
  (screenshot-digest "" :type string)
  (trace-digest     ""  :type string)
  (command-fingerprint 0 :type integer)
  (drift-rationale  ""  :type string)
  (stable-p         nil :type boolean))

(defstruct (scenario-provenance-timeline (:conc-name spt-))
  "Full provenance timeline for one S1-S6 scenario."
  (scenario-id        ""  :type string)
  (entries            nil :type list)   ; list of provenance-timeline-entry
  (fingerprint-lineage nil :type list)  ; list of integers (command-fingerprint per entry)
  (digest-history     nil :type list)   ; list of strings (screenshot-digest per entry)
  (drift-events       nil :type list)   ; list of strings (drift-rationale when drift detected)
  (lineage-stable-p   nil :type boolean)
  (entry-count        0   :type (integer 0)))

(defstruct (playwright-provenance-index (:conc-name ppi-))
  "Aggregate provenance index for S1-S6 scenarios."
  (run-id           ""  :type string)
  (timelines        nil :type list)   ; list of scenario-provenance-timeline
  (all-stable-p     nil :type boolean)
  (total-drift-events 0 :type (integer 0))
  (closure-ready-p  nil :type boolean)
  (timestamp        0   :type integer)
  (alarm-codes      nil :type list))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Pure helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun %compute-command-fingerprint-from-parts (scenario-id rerun-index)
  "Deterministic integer fingerprint from scenario command identity.
   RERUN-INDEX is accepted for API compatibility but does NOT affect
   the fingerprint — reruns of the same scenario use the same command,
   so their fingerprints must be identical."
  (declare (type string scenario-id) (type (integer 0) rerun-index)
           (ignorable rerun-index))
  (reduce #'(lambda (acc c) (logxor (ash acc 5) (char-code c)))
          scenario-id :initial-value 0))

(defun %detect-fingerprint-drift (lineage)
  "Return T if command-fingerprint changes across the lineage list."
  (declare (type list lineage))
  (when (rest lineage)
    (not (every #'= lineage (rest lineage)))))

(defun %build-drift-rationale (prev-digest cur-digest prev-fp cur-fp)
  "Compose a human-readable drift rationale string."
  (declare (type string prev-digest cur-digest) (type integer prev-fp cur-fp))
  (cond
    ((not (string= prev-digest cur-digest))
     (format nil "screenshot-digest changed: ~A -> ~A" prev-digest cur-digest))
    ((not (= prev-fp cur-fp))
     (format nil "command-fingerprint changed: ~D -> ~D" prev-fp cur-fp))
    (t "")))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Entry builder
;;; ─────────────────────────────────────────────────────────────────────────────

(defun build-provenance-timeline-entry
    (scenario-id rerun-index screenshot-digest trace-digest
     &key (timestamp (get-universal-time)) drift-rationale)
  "Build one PROVENANCE-TIMELINE-ENTRY from raw evidence fields.
   DRIFT-RATIONALE defaults to empty string when nil."
  (declare (type string scenario-id screenshot-digest trace-digest)
           (type (integer 0) rerun-index timestamp))
  (let* ((fp     (%compute-command-fingerprint-from-parts scenario-id rerun-index))
         (stable (and (not (string= screenshot-digest ""))
                      (not (string= trace-digest "")))))
    (make-provenance-timeline-entry
     :scenario-id       scenario-id
     :rerun-index       rerun-index
     :timestamp         timestamp
     :screenshot-digest screenshot-digest
     :trace-digest      trace-digest
     :command-fingerprint fp
     :drift-rationale   (or drift-rationale "")
     :stable-p          stable)))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Timeline builder
;;; ─────────────────────────────────────────────────────────────────────────────

(defun build-scenario-provenance-timeline (scenario-id entries)
  "Build a SCENARIO-PROVENANCE-TIMELINE from SCENARIO-ID and a list of
   PROVENANCE-TIMELINE-ENTRY structs in rerun order.
   Computes fingerprint-lineage, digest-history, and drift-events."
  (declare (type string scenario-id) (type list entries))
  (let* ((fingerprints  (mapcar #'pte-command-fingerprint entries))
         (digests       (mapcar #'pte-screenshot-digest   entries))
         (drift-events
          (loop for (prev . rest-entries) on entries
                when rest-entries
                collect
                (let* ((cur  (first rest-entries))
                       (rat  (%build-drift-rationale
                              (pte-screenshot-digest  prev)
                              (pte-screenshot-digest  cur)
                              (pte-command-fingerprint prev)
                              (pte-command-fingerprint cur))))
                  (if (string= rat "") nil rat))
                into all-drift
                finally (return (remove nil all-drift))))
         (lineage-stable (not (%detect-fingerprint-drift fingerprints))))
    (make-scenario-provenance-timeline
     :scenario-id        scenario-id
     :entries            entries
     :fingerprint-lineage fingerprints
     :digest-history     digests
     :drift-events       drift-events
     :lineage-stable-p   lineage-stable
     :entry-count        (length entries))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Index builder
;;; ─────────────────────────────────────────────────────────────────────────────

(defun build-playwright-provenance-index (run-id timelines)
  "Build a PLAYWRIGHT-PROVENANCE-INDEX from RUN-ID and a list of
   SCENARIO-PROVENANCE-TIMELINE structs (one per S1-S6 scenario).
   Enforces Epic 4 policy: all-stable-p requires all timelines stable,
   closure-ready-p requires all-stable-p and zero drift events."
  (declare (type string run-id) (type list timelines))
  (let* ((total-drift  (reduce #'+ timelines
                               :key  #'(lambda (tl) (length (spt-drift-events tl)))
                               :initial-value 0))
         (all-stable   (every #'spt-lineage-stable-p timelines))
         ;; All individual entries must also be stable (non-empty digests)
         (all-entries-stable
          (every (lambda (tl)
                   (every #'pte-stable-p (spt-entries tl)))
                 timelines))
         (closure-ready (and all-stable all-entries-stable (zerop total-drift)))
         (alarms       (append
                        (unless all-stable        '(:fingerprint-lineage-unstable))
                        (unless all-entries-stable '(:entries-unstable))
                        (unless (zerop total-drift) '(:drift-events-detected))
                        (unless closure-ready      '(:closure-not-ready)))))
    (make-playwright-provenance-index
     :run-id           run-id
     :timelines        timelines
     :all-stable-p     all-stable
     :total-drift-events total-drift
     :closure-ready-p  closure-ready
     :timestamp        (get-universal-time)
     :alarm-codes      alarms)))
