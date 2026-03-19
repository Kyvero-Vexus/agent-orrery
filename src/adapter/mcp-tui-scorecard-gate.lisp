;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-scorecard-gate.lisp — Epic 3 T1-T6 completeness scorecard + gate CLI core
;;; Bead: agent-orrery-gmlq

(in-package #:orrery/adapter)

(defstruct (mcp-tui-scenario-score (:conc-name mtss-))
  (scenario-id "" :type string)
  (screenshot-p nil :type boolean)
  (transcript-p nil :type boolean)
  (asciicast-p nil :type boolean)
  (report-p nil :type boolean)
  (score 0 :type integer)
  (pass-p nil :type boolean))

(defstruct (mcp-tui-scorecard-result (:conc-name mtsr-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (scenario-scores nil :type list)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (runner-evidence-manifest string evidence-artifact-kind) (values boolean &optional))
        scenario-has-artifact-kind-p)
 (ftype (function (runner-evidence-manifest string) (values mcp-tui-scenario-score &optional))
        build-tui-scenario-score)
 (ftype (function (string string) (values mcp-tui-scorecard-result &optional))
        evaluate-mcp-tui-scorecard-gate)
 (ftype (function (mcp-tui-scorecard-result) (values string &optional))
        mcp-tui-scorecard-result->json))

(defun scenario-has-artifact-kind-p (manifest scenario-id kind)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id)
           (type evidence-artifact-kind kind))
  (not (null (find-if (lambda (artifact)
                        (and (string= scenario-id (ea-scenario-id artifact))
                             (eq kind (ea-artifact-kind artifact))
                             (ea-present-p artifact)))
                      (rem-artifacts manifest)))))

(defun build-tui-scenario-score (manifest scenario-id)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id))
  (let* ((shot (scenario-has-artifact-kind-p manifest scenario-id :screenshot))
         (tx (scenario-has-artifact-kind-p manifest scenario-id :transcript))
         (cast (scenario-has-artifact-kind-p manifest scenario-id :asciicast))
         (report (scenario-has-artifact-kind-p manifest scenario-id :machine-report))
         (score (+ (if shot 1 0) (if tx 1 0) (if cast 1 0) (if report 1 0)))
         (pass (and shot tx cast report)))
    (make-mcp-tui-scenario-score
     :scenario-id scenario-id
     :screenshot-p shot
     :transcript-p tx
     :asciicast-p cast
     :report-p report
     :score score
     :pass-p pass)))

(defun evaluate-mcp-tui-scorecard-gate (artifacts-dir command)
  "Fail-closed Epic 3 gate.
Requires mcp-tui-driver T1-T6 evidence and canonical deterministic command." 
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((manifest (compile-mcp-tui-evidence-manifest artifacts-dir command))
         (command-ok (string= command *mcp-tui-deterministic-command*))
         (scores nil)
         (missing nil))
    (dolist (sid *mcp-tui-required-scenarios*)
      (let ((row (build-tui-scenario-score manifest sid)))
        (push row scores)
        (unless (mtss-pass-p row)
          (push sid missing))))
    (let* ((rows (nreverse scores))
           (missing-rows (nreverse missing))
           (pass (and command-ok (null missing-rows))))
      (make-mcp-tui-scorecard-result
       :pass-p pass
       :command-match-p command-ok
       :scenario-scores rows
       :missing-scenarios missing-rows
       :detail (format nil "command_ok=~A missing=~D" command-ok (length missing-rows))
       :timestamp (get-universal-time)))))

(defun mcp-tui-scorecard-result->json (result)
  (declare (type mcp-tui-scorecard-result result))
  (format nil
          "{\"pass\":~A,\"command_match\":~A,\"scenario_count\":~D,\"missing\":~D,\"detail\":\"~A\",\"timestamp\":~D}"
          (if (mtsr-pass-p result) "true" "false")
          (if (mtsr-command-match-p result) "true" "false")
          (length (mtsr-scenario-scores result))
          (length (mtsr-missing-scenarios result))
          (mtsr-detail result)
          (mtsr-timestamp result)))
