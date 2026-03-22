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
  (command-hash 0 :type integer)
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
 (ftype (function (string) (values string &optional)) %json-escape)
 (ftype (function (list) (values string &optional)) %string-list->json-array)
 (ftype (function (mcp-tui-scorecard-result) (values string &optional))
        mcp-tui-scorecard-result->json)
 (ftype (function (mcp-tui-scorecard-result) (values string &optional))
        mcp-tui-scorecard-result->detailed-json))

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
       :command-hash (command-fingerprint command)
       :scenario-scores rows
       :missing-scenarios missing-rows
       :detail (format nil "command_ok=~A missing=~D" command-ok (length missing-rows))
       :timestamp (get-universal-time)))))

(defun %json-escape (input)
  (declare (type string input))
  (with-output-to-string (out)
    (loop for ch across input
          do (case ch
               (#\\ (write-string "\\\\" out))
               (#\" (write-string "\\\"" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (t (write-char ch out))))))

(defun %string-list->json-array (items)
  (declare (type list items))
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for item in items
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~A\"" (%json-escape item))))
    (write-string "]" out)))

(defun mcp-tui-scorecard-result->json (result)
  (declare (type mcp-tui-scorecard-result result))
  (format nil
          "{\"pass\":~A,\"command_match\":~A,\"command_hash\":~D,\"scenario_count\":~D,\"missing\":~D,\"missing_scenarios\":~A,\"detail\":\"~A\",\"timestamp\":~D,\"required_runner\":\"mcp-tui-driver\",\"deterministic_command\":\"~A\"}"
          (if (mtsr-pass-p result) "true" "false")
          (if (mtsr-command-match-p result) "true" "false")
          (mtsr-command-hash result)
          (length (mtsr-scenario-scores result))
          (length (mtsr-missing-scenarios result))
          (%string-list->json-array (mtsr-missing-scenarios result))
          (%json-escape (mtsr-detail result))
          (mtsr-timestamp result)
          (%json-escape *mcp-tui-deterministic-command*)))

(defun mcp-tui-scorecard-result->detailed-json (result)
  (declare (type mcp-tui-scorecard-result result))
  (with-output-to-string (out)
    (format out "{\"pass\":~A,\"command_match\":~A,\"command_hash\":~D,\"scenario_count\":~D,\"missing\":~D,\"missing_scenarios\":~A,\"detail\":\"~A\",\"timestamp\":~D,\"required_runner\":\"mcp-tui-driver\",\"deterministic_command\":\"~A\",\"scenarios\":["
            (if (mtsr-pass-p result) "true" "false")
            (if (mtsr-command-match-p result) "true" "false")
            (mtsr-command-hash result)
            (length (mtsr-scenario-scores result))
            (length (mtsr-missing-scenarios result))
            (%string-list->json-array (mtsr-missing-scenarios result))
            (%json-escape (mtsr-detail result))
            (mtsr-timestamp result)
            (%json-escape *mcp-tui-deterministic-command*))
    (loop for row in (mtsr-scenario-scores result)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out
                       "{\"id\":\"~A\",\"score\":~D,\"pass\":~A,\"shot\":~A,\"transcript\":~A,\"cast\":~A,\"report\":~A}"
                       (%json-escape (mtss-scenario-id row))
                       (mtss-score row)
                       (if (mtss-pass-p row) "true" "false")
                       (if (mtss-screenshot-p row) "true" "false")
                       (if (mtss-transcript-p row) "true" "false")
                       (if (mtss-asciicast-p row) "true" "false")
                       (if (mtss-report-p row) "true" "false"))))
    (write-string "]}" out)))
