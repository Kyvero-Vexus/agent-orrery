;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-replay-verdict-emitter.lisp — typed replay verdict + artifact bundle index
;;; Bead: agent-orrery-rf9l

(in-package #:orrery/adapter)

(defstruct (mcp-tui-bundle-row (:conc-name mtbr-))
  (scenario-id "" :type string)
  (screenshot-path "" :type string)
  (transcript-path "" :type string)
  (asciicast-path "" :type string)
  (report-path "" :type string)
  (score 0 :type integer)
  (pass-p nil :type boolean))

(defstruct (mcp-tui-replay-verdict (:conc-name mtrv-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (deterministic-command "" :type string)
  (bundle-rows nil :type list)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (mcp-tui-scenario-score) (values mcp-tui-bundle-row &optional))
        scenario-score->bundle-row)
 (ftype (function (mcp-tui-scorecard-result) (values mcp-tui-replay-verdict &optional))
        scorecard->replay-verdict)
 (ftype (function (string string) (values mcp-tui-replay-verdict &optional))
        evaluate-mcp-tui-replay-verdict)
 (ftype (function (mcp-tui-replay-verdict) (values string &optional))
        mcp-tui-replay-verdict->json))

(defun scenario-score->bundle-row (row)
  (declare (type mcp-tui-scenario-score row))
  (let ((root "test-results/tui-artifacts/"))
    (make-mcp-tui-bundle-row
     :scenario-id (mtss-scenario-id row)
     :screenshot-path (mcp-tui-artifact-path root (mtss-scenario-id row) :screenshot)
     :transcript-path (mcp-tui-artifact-path root (mtss-scenario-id row) :transcript)
     :asciicast-path (mcp-tui-artifact-path root (mtss-scenario-id row) :asciicast)
     :report-path (mcp-tui-artifact-path root (mtss-scenario-id row) :report)
     :score (mtss-score row)
     :pass-p (mtss-pass-p row))))

(defun scorecard->replay-verdict (scorecard)
  (declare (type mcp-tui-scorecard-result scorecard)
           (optimize (safety 3)))
  (let ((rows (mapcar #'scenario-score->bundle-row (mtsr-scenario-scores scorecard))))
    (make-mcp-tui-replay-verdict
     :pass-p (and (mtsr-pass-p scorecard)
                  (mtsr-command-match-p scorecard)
                  (null (mtsr-missing-scenarios scorecard)))
     :command-match-p (mtsr-command-match-p scorecard)
     :deterministic-command *mcp-tui-deterministic-command*
     :bundle-rows rows
     :missing-scenarios (mtsr-missing-scenarios scorecard)
     :detail (format nil "command_ok=~A missing=~D"
                     (mtsr-command-match-p scorecard)
                     (length (mtsr-missing-scenarios scorecard)))
     :timestamp (get-universal-time))))

(defun evaluate-mcp-tui-replay-verdict (artifacts-dir command)
  (declare (type string artifacts-dir command))
  (scorecard->replay-verdict
   (evaluate-mcp-tui-scorecard-gate artifacts-dir command)))

(defun mcp-tui-replay-verdict->json (verdict)
  (declare (type mcp-tui-replay-verdict verdict))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"command_match\":~A,\"deterministic_command\":\"~A\",\"row_count\":~D,\"missing\":~D,\"detail\":\"~A\",\"timestamp\":~D,\"rows\":["
            (if (mtrv-pass-p verdict) "true" "false")
            (if (mtrv-command-match-p verdict) "true" "false")
            (mtrv-deterministic-command verdict)
            (length (mtrv-bundle-rows verdict))
            (length (mtrv-missing-scenarios verdict))
            (mtrv-detail verdict)
            (mtrv-timestamp verdict))
    (loop for row in (mtrv-bundle-rows verdict)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out
                       "{\"id\":\"~A\",\"score\":~D,\"pass\":~A,\"shot\":\"~A\",\"transcript\":\"~A\",\"cast\":\"~A\",\"report\":\"~A\"}"
                       (mtbr-scenario-id row)
                       (mtbr-score row)
                       (if (mtbr-pass-p row) "true" "false")
                       (mtbr-screenshot-path row)
                       (mtbr-transcript-path row)
                       (mtbr-asciicast-path row)
                       (mtbr-report-path row))))
    (write-string "]}" out)))
