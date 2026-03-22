;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-evidence-validator.lisp — Typed T1-T6 evidence validator + closure verdict emitter
;;; Bead: agent-orrery-1ts
;;;
;;; Validates mcp-tui-driver T1-T6 execution evidence, enforces deterministic
;;; command contract, per-scenario artifact completeness, and emits a typed
;;; closure verdict object consumed by Epic 3 completion gates.

(in-package #:orrery/adapter)

;;; ============================================================
;;; Failure Diagnostic Types
;;; ============================================================

(defstruct (t1t6-scenario-failure
            (:constructor make-t1t6-scenario-failure)
            (:conc-name t1t6sf-)
            (:copier nil))
  "Failure diagnostic for a single T1-T6 scenario."
  (scenario-id  ""     :type string  :read-only t)
  (missing-artifacts nil :type list  :read-only t)
  (artifact-score 0   :type (integer 0 4) :read-only t)
  (reason-code  :incomplete :type symbol :read-only t))

(defstruct (t1t6-closure-verdict
            (:constructor make-t1t6-closure-verdict)
            (:conc-name t1t6cv-)
            (:copier nil))
  "Typed closure verdict for Epic 3 T1-T6 evidence gate.
   Consumed by Epic 3 completion gates; fail closed on pass-p=NIL."
  (pass-p              nil :type boolean  :read-only t)
  (command-ok-p        nil :type boolean  :read-only t)
  (deterministic-command "" :type string  :read-only t)
  (command-hash        0   :type integer  :read-only t)
  (scenarios-required  nil :type list     :read-only t)
  (scenarios-passed    nil :type list     :read-only t)
  (scenario-failures   nil :type list     :read-only t)
  (missing-scenarios   nil :type list     :read-only t)
  (failure-diagnostics nil :type list     :read-only t)
  (detail              ""  :type string   :read-only t)
  (timestamp           0   :type integer  :read-only t))

;;; ============================================================
;;; Declarations
;;; ============================================================

(declaim
 (ftype (function (mcp-tui-scorecard-result) (values t1t6-closure-verdict &optional))
        scorecard->t1t6-closure-verdict)
 (ftype (function (string string) (values t1t6-closure-verdict &optional))
        evaluate-t1t6-evidence-validator)
 (ftype (function (t1t6-closure-verdict) (values string &optional))
        t1t6-closure-verdict->json)
 (ftype (function (t1t6-scenario-failure) (values string &optional))
        t1t6sf->json))

;;; ============================================================
;;; Failure reason classification
;;; ============================================================

(defun %classify-failure-reason (missing-kinds score)
  "Return a reason-code keyword for the failure given MISSING-KINDS and SCORE."
  (declare (type list missing-kinds)
           (type integer score))
  (cond
    ((= score 0) :no-artifacts)
    ((member :screenshot missing-kinds) :missing-screenshot)
    ((member :transcript missing-kinds) :missing-transcript)
    ((member :asciicast missing-kinds)  :missing-asciicast)
    ((member :machine-report missing-kinds) :missing-report)
    (t :incomplete)))

;;; ============================================================
;;; Scenario failure extraction
;;; ============================================================

(defun %scenario-score->failure (row)
  "Convert a failing SCENARIO-SCORE row into a T1T6-SCENARIO-FAILURE."
  (declare (type mcp-tui-scenario-score row))
  (let ((missing nil))
    (unless (mtss-screenshot-p row) (push :screenshot missing))
    (unless (mtss-transcript-p row) (push :transcript missing))
    (unless (mtss-asciicast-p row)  (push :asciicast missing))
    (unless (mtss-report-p row)     (push :machine-report missing))
    (let ((missing-kinds (nreverse missing)))
      (make-t1t6-scenario-failure
       :scenario-id       (mtss-scenario-id row)
       :missing-artifacts missing-kinds
       :artifact-score    (mtss-score row)
       :reason-code       (%classify-failure-reason missing-kinds (mtss-score row))))))

;;; ============================================================
;;; Core: scorecard -> verdict
;;; ============================================================

(defun scorecard->t1t6-closure-verdict (scorecard)
  "Translate a MCP-TUI-SCORECARD-RESULT into a typed T1T6-CLOSURE-VERDICT."
  (declare (type mcp-tui-scorecard-result scorecard)
           (optimize (safety 3)))
  (let* ((all-scores (mtsr-scenario-scores scorecard))
         (pass-rows  (remove-if-not #'mtss-pass-p all-scores))
         (fail-rows  (remove-if     #'mtss-pass-p all-scores))
         (failures   (mapcar #'%scenario-score->failure fail-rows))
         (passed-ids (mapcar #'mtss-scenario-id pass-rows))
         (failed-ids (mapcar #'mtss-scenario-id fail-rows))
         (missing    (mtsr-missing-scenarios scorecard))
         (command-ok (mtsr-command-match-p scorecard))
         (verdict-pass (and (mtsr-pass-p scorecard)
                            command-ok
                            (null fail-rows)
                            (null missing))))
    (make-t1t6-closure-verdict
     :pass-p              verdict-pass
     :command-ok-p        command-ok
     :deterministic-command *mcp-tui-deterministic-command*
     :command-hash        (mtsr-command-hash scorecard)
     :scenarios-required  (copy-list *mcp-tui-required-scenarios*)
     :scenarios-passed    passed-ids
     :scenario-failures   failed-ids
     :missing-scenarios   missing
     :failure-diagnostics failures
     :detail              (format nil
                                  "pass=~A cmd_ok=~A passed=~D/~D failed=~D missing=~D"
                                  verdict-pass
                                  command-ok
                                  (length pass-rows)
                                  (length all-scores)
                                  (length fail-rows)
                                  (length missing))
     :timestamp (get-universal-time))))

(defun evaluate-t1t6-evidence-validator (artifacts-dir command)
  "Run full T1-T6 evidence validation against ARTIFACTS-DIR with COMMAND.
   Returns a T1T6-CLOSURE-VERDICT; gates must fail closed unless PASS-P is true."
  (declare (type string artifacts-dir command))
  (let ((scorecard (evaluate-mcp-tui-scorecard-gate artifacts-dir command)))
    (scorecard->t1t6-closure-verdict scorecard)))

;;; ============================================================
;;; JSON serialisation
;;; ============================================================

(defun t1t6sf->json (failure)
  "Serialise a T1T6-SCENARIO-FAILURE to a JSON object string."
  (declare (type t1t6-scenario-failure failure))
  (format nil
          "{\"scenario_id\":\"~A\",\"missing_artifacts\":~A,\"artifact_score\":~D,\"reason_code\":\"~A\"}"
          (%json-escape (t1t6sf-scenario-id failure))
          (%string-list->json-array
           (mapcar (lambda (k) (string-downcase (symbol-name k)))
                   (t1t6sf-missing-artifacts failure)))
          (t1t6sf-artifact-score failure)
          (%json-escape (string-downcase (symbol-name (t1t6sf-reason-code failure))))))

(defun t1t6-closure-verdict->json (verdict)
  "Serialise a T1T6-CLOSURE-VERDICT to a JSON object string."
  (declare (type t1t6-closure-verdict verdict))
  (format nil
          (concatenate 'string
                       "{"
                       "\"pass\":~A,"
                       "\"command_ok\":~A,"
                       "\"deterministic_command\":\"~A\","
                       "\"command_hash\":~D,"
                       "\"scenarios_required\":~A,"
                       "\"scenarios_passed\":~A,"
                       "\"scenario_failures\":~A,"
                       "\"missing_scenarios\":~A,"
                       "\"failure_diagnostics\":[~{~A~^,~}],"
                       "\"detail\":\"~A\","
                       "\"timestamp\":~D"
                       "}")
          (if (t1t6cv-pass-p verdict) "true" "false")
          (if (t1t6cv-command-ok-p verdict) "true" "false")
          (%json-escape (t1t6cv-deterministic-command verdict))
          (t1t6cv-command-hash verdict)
          (%string-list->json-array (t1t6cv-scenarios-required verdict))
          (%string-list->json-array (t1t6cv-scenarios-passed verdict))
          (%string-list->json-array (t1t6cv-scenario-failures verdict))
          (%string-list->json-array (t1t6cv-missing-scenarios verdict))
          (mapcar #'t1t6sf->json (t1t6cv-failure-diagnostics verdict))
          (%json-escape (t1t6cv-detail verdict))
          (t1t6cv-timestamp verdict)))
