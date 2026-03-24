;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-env-fingerprint-normalizer.lisp
;;;   Typed CL normalizer for mcp-tui-driver T1-T6 environment fingerprints and
;;;   a drift explainer that classifies rerun variance with machine-checkable
;;;   rationale JSON for Epic 3 closure gates.
;;;
;;; Bead: agent-orrery-t1yb
;;;
;;; Deterministic command: cd e2e-tui && ./run-tui-e2e-t1-t6.sh
;;; Design doc: /home/slime/projects/emacsen-design-docs/agent-orrery/
;;;             epic-3-env-fingerprint-normalizer-t1yb.md

(in-package #:orrery/adapter)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Type declarations
;;; ─────────────────────────────────────────────────────────────────────────────

(deftype env-drift-class ()
  '(member :env-mismatch :command-drift :flag-drift :stable))

(deftype env-gate-verdict ()
  '(member :stable :drifted :rejected))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: env-fingerprint
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (env-fingerprint (:conc-name efp-))
  "Snapshot of the runtime environment at a T1-T6 deterministic run."
  (lisp-impl          ""  :type string)   ; e.g. "SBCL 2.4.0"
  (os-info            ""  :type string)
  (harness-flags      nil :type list)     ; alist: (flag-name-string . value-string)
  (deterministic-command "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" :type string)
  (command-fingerprint "" :type string)   ; hex sxhash of deterministic-command
  (captured-at        0   :type integer))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: env-drift-record
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (env-drift-record (:conc-name edr-))
  "Per-field variance record comparing baseline to current env-fingerprint."
  (drift-class        :stable :type env-drift-class)
  (field-name         ""  :type string)
  (old-value          ""  :type string)
  (new-value          ""  :type string)
  (rationale          ""  :type string))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADT: env-drift-report
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (env-drift-report (:conc-name ereport-))
  "Full cross-field drift report comparing two env-fingerprints."
  (baseline-fp        nil :type (or null env-fingerprint))
  (current-fp         nil :type (or null env-fingerprint))
  (records            nil :type list)    ; list of env-drift-record
  (gate-verdict       :stable :type env-gate-verdict)
  (drift-count        0   :type fixnum)
  (timestamp          0   :type integer))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Constants
;;; ─────────────────────────────────────────────────────────────────────────────

(defparameter *t1-t6-canonical-env-command*
  "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
  "Canonical deterministic command for T1-T6 env-fingerprint normalization.")

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Declaims
;;; ─────────────────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (&key (:lisp-impl string)
                        (:os-info string)
                        (:harness-flags list))
                  (values env-fingerprint &optional))
        capture-env-fingerprint)
 (ftype (function (env-fingerprint) (values env-fingerprint &optional))
        normalize-env-fingerprint)
 (ftype (function (env-fingerprint env-fingerprint) (values list &optional))
        diff-env-fingerprints)
 (ftype (function (env-fingerprint env-fingerprint) (values env-drift-report &optional))
        build-env-drift-report)
 (ftype (function (env-drift-report) (values env-gate-verdict &optional))
        evaluate-env-drift-gate)
 (ftype (function (env-fingerprint) (values string &optional))
        env-fingerprint->json)
 (ftype (function (env-drift-report) (values string &optional))
        env-drift-report->json))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Construction + normalization
;;; ─────────────────────────────────────────────────────────────────────────────

(defun capture-env-fingerprint (&key
                                  (lisp-impl
                                   (format nil "~A ~A"
                                           (lisp-implementation-type)
                                           (lisp-implementation-version)))
                                  (os-info
                                   (software-type))
                                  (harness-flags nil))
  "Capture current runtime env as an env-fingerprint.
   Locks deterministic-command to the canonical T1-T6 command."
  (declare (type string lisp-impl os-info)
           (type list harness-flags))
  (let ((cmd *t1-t6-canonical-env-command*))
    (make-env-fingerprint
     :lisp-impl lisp-impl
     :os-info (or os-info "")
     :harness-flags harness-flags
     :deterministic-command cmd
     :command-fingerprint (format nil "~16,'0X" (sxhash cmd))
     :captured-at (get-universal-time))))

(defun normalize-env-fingerprint (fp)
  "Return a normalized copy of FP:
   - trims whitespace from lisp-impl and os-info
   - ensures command-fingerprint is consistent with deterministic-command
   - enforces canonical command string"
  (declare (type env-fingerprint fp))
  (let* ((cmd (string-trim '(#\Space #\Tab #\Newline)
                            (efp-deterministic-command fp)))
         (canonical-cmd *t1-t6-canonical-env-command*)
         ;; Normalize to canonical command
         (effective-cmd (if (string= cmd canonical-cmd) cmd canonical-cmd))
         (fp-hash (format nil "~16,'0X" (sxhash effective-cmd))))
    (make-env-fingerprint
     :lisp-impl (string-trim '(#\Space #\Tab #\Newline) (efp-lisp-impl fp))
     :os-info   (string-trim '(#\Space #\Tab #\Newline) (efp-os-info fp))
     :harness-flags (efp-harness-flags fp)
     :deterministic-command effective-cmd
     :command-fingerprint fp-hash
     :captured-at (efp-captured-at fp))))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Drift detection
;;; ─────────────────────────────────────────────────────────────────────────────

(defun diff-env-fingerprints (baseline current)
  "Compare BASELINE and CURRENT env-fingerprints field by field.
   Returns a list of env-drift-record for any differing fields."
  (declare (type env-fingerprint baseline current))
  (let ((records '()))
    ;; Check lisp-impl
    (unless (string= (efp-lisp-impl baseline) (efp-lisp-impl current))
      (push (make-env-drift-record
             :drift-class :env-mismatch
             :field-name "lisp_impl"
             :old-value (efp-lisp-impl baseline)
             :new-value (efp-lisp-impl current)
             :rationale (format nil "Lisp implementation changed: '~A' -> '~A'"
                                (efp-lisp-impl baseline)
                                (efp-lisp-impl current)))
            records))
    ;; Check os-info
    (unless (string= (efp-os-info baseline) (efp-os-info current))
      (push (make-env-drift-record
             :drift-class :env-mismatch
             :field-name "os_info"
             :old-value (efp-os-info baseline)
             :new-value (efp-os-info current)
             :rationale (format nil "OS info changed: '~A' -> '~A'"
                                (efp-os-info baseline)
                                (efp-os-info current)))
            records))
    ;; Check command fingerprint
    (unless (string= (efp-command-fingerprint baseline)
                     (efp-command-fingerprint current))
      (push (make-env-drift-record
             :drift-class :command-drift
             :field-name "command_fingerprint"
             :old-value (efp-command-fingerprint baseline)
             :new-value (efp-command-fingerprint current)
             :rationale (format nil "Deterministic command fingerprint drifted: ~A -> ~A"
                                (efp-command-fingerprint baseline)
                                (efp-command-fingerprint current)))
            records))
    ;; Check harness flags
    (let ((baseline-flags (efp-harness-flags baseline))
          (current-flags  (efp-harness-flags current)))
      (dolist (pair baseline-flags)
        (let* ((flag-name (car pair))
               (old-val   (cdr pair))
               (new-entry (assoc flag-name current-flags :test #'equal)))
          (cond
            ((null new-entry)
             (push (make-env-drift-record
                    :drift-class :flag-drift
                    :field-name (format nil "harness_flag/~A" flag-name)
                    :old-value old-val
                    :new-value ""
                    :rationale (format nil "Harness flag '~A' removed in current run"
                                       flag-name))
                   records))
            ((not (equal old-val (cdr new-entry)))
             (push (make-env-drift-record
                    :drift-class :flag-drift
                    :field-name (format nil "harness_flag/~A" flag-name)
                    :old-value old-val
                    :new-value (cdr new-entry)
                    :rationale (format nil "Harness flag '~A' changed: '~A' -> '~A'"
                                       flag-name old-val (cdr new-entry)))
                   records))))))
    (nreverse records)))

(defun build-env-drift-report (baseline current)
  "Build an env-drift-report comparing BASELINE and CURRENT env-fingerprints.
   Fails closed: any drift class produces :drifted or :rejected gate verdict."
  (declare (type env-fingerprint baseline current))
  (let* ((records    (diff-env-fingerprints baseline current))
         (drift-count (length records))
         (has-command-drift-p
           (some (lambda (r) (eq (edr-drift-class r) :command-drift)) records))
         (gate-verdict
           (cond
             ((zerop drift-count)       :stable)
             (has-command-drift-p       :rejected)
             (t                         :drifted))))
    (make-env-drift-report
     :baseline-fp baseline
     :current-fp  current
     :records     records
     :gate-verdict gate-verdict
     :drift-count drift-count
     :timestamp   (get-universal-time))))

(defun evaluate-env-drift-gate (report)
  "Return the gate verdict from REPORT.
   :stable   — no drift detected
   :drifted  — env/flag drift but command is unchanged
   :rejected — command fingerprint drifted (fail closed)"
  (declare (type env-drift-report report))
  (ereport-gate-verdict report))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; JSON serialization
;;; ─────────────────────────────────────────────────────────────────────────────

(defun harness-flags->json (flags)
  "Serialize harness flags alist to a JSON object string."
  (declare (type list flags))
  (if (null flags)
      "{}"
      (format nil "{~{\"~A\":\"~A\"~^,~}}"
              (loop for (k . v) in flags collect k collect v))))

(defun env-fingerprint->json (fp)
  "Serialize an env-fingerprint to a JSON string."
  (declare (type env-fingerprint fp))
  (format nil
   "{\"lisp_impl\":\"~A\",\"os_info\":\"~A\",\"deterministic_command\":\"~A\",\"command_fingerprint\":\"~A\",\"harness_flags\":~A,\"captured_at\":~A}"
   (efp-lisp-impl fp)
   (efp-os-info fp)
   (efp-deterministic-command fp)
   (efp-command-fingerprint fp)
   (harness-flags->json (efp-harness-flags fp))
   (efp-captured-at fp)))

(defun edr->json (record)
  "Serialize a single env-drift-record to a JSON object string."
  (declare (type env-drift-record record))
  (format nil
   "{\"drift_class\":\"~A\",\"field\":\"~A\",\"old\":\"~A\",\"new\":\"~A\",\"rationale\":\"~A\"}"
   (symbol-name (edr-drift-class record))
   (edr-field-name record)
   (edr-old-value record)
   (edr-new-value record)
   (edr-rationale record)))

(defun env-drift-report->json (report)
  "Serialize an env-drift-report to a machine-checkable JSON string."
  (declare (type env-drift-report report))
  (format nil
   "{\"gate_verdict\":\"~A\",\"drift_count\":~A,\"timestamp\":~A,\"baseline\":~A,\"current\":~A,\"records\":[~{~A~^,~}]}"
   (symbol-name (ereport-gate-verdict report))
   (ereport-drift-count report)
   (ereport-timestamp report)
   (if (ereport-baseline-fp report)
       (env-fingerprint->json (ereport-baseline-fp report))
       "null")
   (if (ereport-current-fp report)
       (env-fingerprint->json (ereport-current-fp report))
       "null")
   (mapcar #'edr->json (ereport-records report))))
