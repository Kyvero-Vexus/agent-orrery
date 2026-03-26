;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-fixture-checksum-registry.lisp
;;;   Typed CL fixture-checksum registry for mcp-tui-driver T1-T6 runs.
;;;   Stores deterministic command fingerprints, transcript digest sets,
;;;   artifact checksum maps, and rerun consistency verdicts.
;;;   Emits machine-checkable JSON diagnostics; fails closed on drift or
;;;   missing scenario artifacts.
;;;
;;; Bead: agent-orrery-d2it
;;;
;;; Deterministic command: cd e2e-tui && ./run-tui-e2e-t1-t6.sh
;;; Design doc: /home/slime/projects/emacsen-design-docs/agent-orrery/
;;;             epic-3-fixture-checksum-registry-d2it.md

(in-package #:orrery/adapter)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Type declarations
;;; ─────────────────────────────────────────────────────────────────────────────

(deftype t1-t6-scenario-id ()
  '(member :T1 :T2 :T3 :T4 :T5 :T6))

(deftype checksum-verdict ()
  '(member :pass :drift :missing))

(deftype registry-closure-verdict ()
  '(member :closed :open :rejected))

(deftype rerun-consistency-status ()
  '(member :stable :drifted :missing))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: fixture-checksum-entry
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (fixture-checksum-entry (:conc-name fce-))
  "Immutable per-scenario registry entry holding command fingerprint,
   transcript digest, artifact checksum map, and closure verdict."
  (scenario-id          :T1  :type t1-t6-scenario-id)
  (command-fingerprint  ""   :type string)   ; hex string of sxhash of canonical command
  (transcript-digest    ""   :type string)   ; hex string of transcript digest
  (artifact-checksum-map nil :type list)     ; alist: ("transcript"|"screenshot"|... . sha256-hex)
  (captured-at          0    :type integer)  ; get-universal-time
  (verdict              :missing :type checksum-verdict)
  (drift-keys           nil  :type list)     ; list of artifact-kind strings that drifted
  (missing-keys         nil  :type list))    ; list of artifact-kind strings that are absent

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: fixture-checksum-registry
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (fixture-checksum-registry (:conc-name fcr-))
  "Append-only registry of fixture-checksum-entries for all T1-T6 scenarios."
  (entries              nil  :type list)          ; list of fixture-checksum-entry
  (canonical-command    "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" :type string)
  (run-id               ""   :type string)
  (closure-verdict      :open :type registry-closure-verdict)
  (drift-count          0    :type fixnum)
  (missing-count        0    :type fixnum)
  (timestamp            0    :type integer))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: rerun-consistency-verdict
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (rerun-consistency-verdict (:conc-name rcv-))
  "Cross-run comparison for a single T1-T6 scenario."
  (scenario-id          :T1  :type t1-t6-scenario-id)
  (status               :missing :type rerun-consistency-status)
  (old-digest           ""   :type string)
  (new-digest           ""   :type string)
  (drift-explanation    ""   :type string))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Constants
;;; ─────────────────────────────────────────────────────────────────────────────

(defparameter *t1-t6-canonical-command*
  "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
  "Canonical deterministic command for Epic 3 mcp-tui-driver T1-T6 runs.")

(defparameter *t1-t6-required-artifact-kinds*
  '("transcript" "screenshot" "asciicast" "report")
  "Artifact kinds required for each T1-T6 scenario in the checksum registry.")

(defparameter *t1-t6-all-scenario-ids*
  '(:T1 :T2 :T3 :T4 :T5 :T6)
  "All six scenario identifiers that must be registered.")

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Declaims
;;; ─────────────────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string) (values string &optional))
        hex-fingerprint)
 (ftype (function (list list) (values list list &optional))
        compare-checksum-maps)
 (ftype (function (t1-t6-scenario-id list string) (values fixture-checksum-entry &optional))
        make-checksum-entry)
 (ftype (function (fixture-checksum-registry fixture-checksum-entry)
                  (values fixture-checksum-registry &optional))
        registry-add-entry)
 (ftype (function (list) (values fixture-checksum-registry &optional))
        build-registry-from-entries)
 (ftype (function (fixture-checksum-registry) (values registry-closure-verdict &optional))
        evaluate-registry-closure)
 (ftype (function (fixture-checksum-entry fixture-checksum-entry)
                  (values rerun-consistency-verdict &optional))
        compare-entries-for-consistency)
 (ftype (function (fixture-checksum-registry fixture-checksum-registry)
                  (values list &optional))
        compute-rerun-consistency-verdicts)
 (ftype (function (fixture-checksum-registry) (values string &optional))
        registry->json)
 (ftype (function (list) (values string &optional))
        rerun-verdicts->json))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun hex-fingerprint (s)
  "Return a deterministic hex string fingerprint of string S via sxhash."
  (declare (type string s))
  (format nil "~16,'0X" (sxhash s)))

(defun compare-checksum-maps (old-map new-map)
  "Compare two alist checksum maps.
   Returns (values drifted-keys missing-keys) as lists of strings."
  (declare (type list old-map new-map))
  (let ((drifted '())
        (missing '()))
    (dolist (pair old-map)
      (let* ((kind (car pair))
             (old-digest (cdr pair))
             (new-entry (assoc kind new-map :test #'equal)))
        (cond
          ((null new-entry)
           (push kind missing))
          ((not (equal old-digest (cdr new-entry)))
           (push kind drifted)))))
    (values (nreverse drifted) (nreverse missing))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Construction
;;; ─────────────────────────────────────────────────────────────────────────────

(defun make-checksum-entry (scenario-id artifact-checksum-map transcript-digest)
  "Construct a fixture-checksum-entry for SCENARIO-ID.
   ARTIFACT-CHECKSUM-MAP is an alist of (kind . digest-hex).
   Derives verdict: :pass if all required artifact kinds present, else :missing."
  (declare (type t1-t6-scenario-id scenario-id)
           (type list artifact-checksum-map)
           (type string transcript-digest))
  (let* ((command-fp (hex-fingerprint *t1-t6-canonical-command*))
         (missing-keys
           (remove-if (lambda (kind)
                        (assoc kind artifact-checksum-map :test #'equal))
                      *t1-t6-required-artifact-kinds*))
         (verdict (if (null missing-keys) :pass :missing)))
    (make-fixture-checksum-entry
     :scenario-id scenario-id
     :command-fingerprint command-fp
     :transcript-digest transcript-digest
     :artifact-checksum-map artifact-checksum-map
     :captured-at (get-universal-time)
     :verdict verdict
     :drift-keys '()
     :missing-keys missing-keys)))

(defun registry-add-entry (registry entry)
  "Return a new registry with ENTRY appended.
   Recalculates closure verdict, drift-count, missing-count."
  (declare (type fixture-checksum-registry registry)
           (type fixture-checksum-entry entry))
  (let* ((new-entries (append (fcr-entries registry) (list entry))))
    (build-registry-from-entries new-entries)))

(defun build-registry-from-entries (entries)
  "Build a fresh fixture-checksum-registry from a list of fixture-checksum-entries.
   Evaluates closure verdict and tallies drift/missing counts."
  (declare (type list entries))
  (let* ((drift-count  (count :drift   entries :key #'fce-verdict))
         (missing-count (count :missing entries :key #'fce-verdict))
         (all-present-p (= (length entries) (length *t1-t6-all-scenario-ids*)))
         (closure-verdict
           (cond
             ((not all-present-p)              :open)
             ((or (> drift-count 0)
                  (> missing-count 0))         :rejected)
             (t                                :closed))))
    (make-fixture-checksum-registry
     :entries entries
     :canonical-command *t1-t6-canonical-command*
     :run-id (hex-fingerprint (format nil "~A" (get-universal-time)))
     :closure-verdict closure-verdict
     :drift-count drift-count
     :missing-count missing-count
     :timestamp (get-universal-time))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Gate evaluation
;;; ─────────────────────────────────────────────────────────────────────────────

(defun evaluate-registry-closure (registry)
  "Return the closure verdict for REGISTRY.
   :closed — all six scenarios pass with no drift/missing.
   :rejected — drift or missing artifacts detected.
   :open — fewer than six scenarios registered."
  (declare (type fixture-checksum-registry registry))
  (fcr-closure-verdict registry))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Cross-run rerun consistency
;;; ─────────────────────────────────────────────────────────────────────────────

(defun compare-entries-for-consistency (old-entry new-entry)
  "Compare OLD-ENTRY and NEW-ENTRY for the same scenario.
   Returns a rerun-consistency-verdict."
  (declare (type fixture-checksum-entry old-entry)
           (type fixture-checksum-entry new-entry))
  (let ((scenario-id (fce-scenario-id old-entry))
        (old-digest  (fce-transcript-digest old-entry))
        (new-digest  (fce-transcript-digest new-entry)))
    (cond
      ((string= "" new-digest)
       (make-rerun-consistency-verdict
        :scenario-id scenario-id
        :status :missing
        :old-digest old-digest
        :new-digest new-digest
        :drift-explanation "New entry has empty transcript digest"))
      ((string= old-digest new-digest)
       (make-rerun-consistency-verdict
        :scenario-id scenario-id
        :status :stable
        :old-digest old-digest
        :new-digest new-digest
        :drift-explanation ""))
      (t
       (make-rerun-consistency-verdict
        :scenario-id scenario-id
        :status :drifted
        :old-digest old-digest
        :new-digest new-digest
        :drift-explanation
        (format nil "Transcript digest changed: ~A -> ~A"
                old-digest new-digest))))))

(defun compute-rerun-consistency-verdicts (old-registry new-registry)
  "Compare OLD-REGISTRY and NEW-REGISTRY scenario-by-scenario.
   Returns a list of rerun-consistency-verdict, one per registered scenario.
   Fails closed: any scenario missing from new-registry yields :missing status."
  (declare (type fixture-checksum-registry old-registry)
           (type fixture-checksum-registry new-registry))
  (mapcar
   (lambda (scenario-id)
     (let ((old-e (find scenario-id (fcr-entries old-registry)
                        :key #'fce-scenario-id))
           (new-e (find scenario-id (fcr-entries new-registry)
                        :key #'fce-scenario-id)))
       (cond
         ((and old-e new-e)
          (compare-entries-for-consistency old-e new-e))
         ((and (null old-e) new-e)
          ;; First time seeing this scenario — treat as stable baseline
          (make-rerun-consistency-verdict
           :scenario-id scenario-id
           :status :stable
           :old-digest ""
           :new-digest (fce-transcript-digest new-e)
           :drift-explanation "No prior baseline; recording as stable"))
         (t
          ;; Missing from new run — fail closed
          (make-rerun-consistency-verdict
           :scenario-id scenario-id
           :status :missing
           :old-digest (if old-e (fce-transcript-digest old-e) "")
           :new-digest ""
           :drift-explanation
           (format nil "Scenario ~A absent from new registry run" scenario-id))))))
   *t1-t6-all-scenario-ids*))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; JSON serialization
;;; ─────────────────────────────────────────────────────────────────────────────

(defun checksum-map->json-array (alist)
  "Serialize an alist of (kind . digest) to a JSON object string."
  (declare (type list alist))
  (if (null alist)
      "{}"
      (format nil "{~{\"~A\":\"~A\"~^,~}}"
              (loop for (k . v) in alist collect k collect v))))

(defun fce->json (entry)
  "Serialize a single fixture-checksum-entry to a JSON object string."
  (declare (type fixture-checksum-entry entry))
  (format nil
   "{\"scenario_id\":\"~A\",\"command_fingerprint\":\"~A\",\"transcript_digest\":\"~A\",\"artifact_checksums\":~A,\"verdict\":\"~A\",\"drift_keys\":[~{\"~A\"~^,~}],\"missing_keys\":[~{\"~A\"~^,~}],\"captured_at\":~A}"
   (symbol-name (fce-scenario-id entry))
   (fce-command-fingerprint entry)
   (fce-transcript-digest entry)
   (checksum-map->json-array (fce-artifact-checksum-map entry))
   (symbol-name (fce-verdict entry))
   (fce-drift-keys entry)
   (fce-missing-keys entry)
   (fce-captured-at entry)))

(defun registry->json (registry)
  "Serialize the full fixture-checksum-registry to a JSON string.
   Machine-checkable format for CI consumption."
  (declare (type fixture-checksum-registry registry))
  (let* ((entries-json
          (format nil "[~{~A~^,~}]"
                  (mapcar #'fce->json (fcr-entries registry)))))
    (format nil
     "{\"canonical_command\":\"~A\",\"run_id\":\"~A\",\"closure_verdict\":\"~A\",\"drift_count\":~A,\"missing_count\":~A,\"timestamp\":~A,\"entries\":~A}"
     (fcr-canonical-command registry)
     (fcr-run-id registry)
     (symbol-name (fcr-closure-verdict registry))
     (fcr-drift-count registry)
     (fcr-missing-count registry)
     (fcr-timestamp registry)
     entries-json)))

(defun rcv->json (verdict)
  "Serialize a single rerun-consistency-verdict to a JSON object string."
  (declare (type rerun-consistency-verdict verdict))
  (format nil
   "{\"scenario_id\":\"~A\",\"status\":\"~A\",\"old_digest\":\"~A\",\"new_digest\":\"~A\",\"drift_explanation\":\"~A\"}"
   (symbol-name (rcv-scenario-id verdict))
   (symbol-name (rcv-status verdict))
   (rcv-old-digest verdict)
   (rcv-new-digest verdict)
   (rcv-drift-explanation verdict)))

(defun rerun-verdicts->json (verdicts)
  "Serialize a list of rerun-consistency-verdicts to a JSON array string."
  (declare (type list verdicts))
  (let* ((any-drift-p   (some (lambda (v) (eq (rcv-status v) :drifted)) verdicts))
         (any-missing-p (some (lambda (v) (eq (rcv-status v) :missing)) verdicts))
         (gate-verdict  (cond (any-missing-p "REJECTED")
                              (any-drift-p   "DRIFTED")
                              (t             "STABLE"))))
    (format nil
     "{\"gate_verdict\":\"~A\",\"verdicts\":[~{~A~^,~}]}"
     gate-verdict
     (mapcar #'rcv->json verdicts))))
