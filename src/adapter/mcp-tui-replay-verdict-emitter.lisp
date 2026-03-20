;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-replay-verdict-emitter.lisp — typed replay verdict + artifact bundle index
;;; Bead: agent-orrery-rf9l

(in-package #:orrery/adapter)

(defstruct (mcp-tui-bundle-row (:conc-name mtbr-))
  (scenario-id "" :type string)
  (screenshot-path "" :type string)
  (transcript-path "" :type string)
  (transcript-digest "" :type string)
  (asciicast-path "" :type string)
  (report-path "" :type string)
  (score 0 :type integer)
  (pass-p nil :type boolean))

(defstruct (mcp-tui-replay-verdict (:conc-name mtrv-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (command-fingerprint 0 :type integer)
  (deterministic-command "" :type string)
  (bundle-rows nil :type list)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string) (values string &optional)) %safe-file-sha256)
 (ftype (function (runner-evidence-manifest string evidence-artifact-kind)
                  (values string &optional))
        %manifest-artifact-path)
 (ftype (function (mcp-tui-scenario-score runner-evidence-manifest)
                  (values mcp-tui-bundle-row &optional))
        scenario-score->bundle-row)
 (ftype (function (mcp-tui-scorecard-result runner-evidence-manifest)
                  (values mcp-tui-replay-verdict &optional))
        scorecard->replay-verdict)
 (ftype (function (string string) (values mcp-tui-replay-verdict &optional))
        evaluate-mcp-tui-replay-verdict)
 (ftype (function (mcp-tui-replay-verdict) (values string &optional))
        mcp-tui-replay-verdict->json))

(defun %safe-file-sha256 (path)
  (declare (type string path))
  (if (and (probe-file path)
           (> (%tui-artifact-size-bytes path) 0))
      (file-sha256 path)
      ""))

(defun %manifest-artifact-path (manifest scenario-id kind)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id)
           (type evidence-artifact-kind kind))
  (let ((hit (find-if (lambda (artifact)
                        (and (string= scenario-id (normalize-scenario-id (ea-scenario-id artifact)))
                             (eq kind (ea-artifact-kind artifact))
                             (ea-present-p artifact)))
                      (rem-artifacts manifest))))
    (if hit (ea-path hit) "")))

(defun scenario-score->bundle-row (row manifest)
  (declare (type mcp-tui-scenario-score row)
           (type runner-evidence-manifest manifest))
  (let* ((sid (mtss-scenario-id row))
         (screenshot-path (%manifest-artifact-path manifest sid :screenshot))
         (transcript-path (%manifest-artifact-path manifest sid :transcript))
         (asciicast-path (%manifest-artifact-path manifest sid :asciicast))
         (report-path (%manifest-artifact-path manifest sid :machine-report)))
    (make-mcp-tui-bundle-row
     :scenario-id sid
     :screenshot-path screenshot-path
     :transcript-path transcript-path
     :transcript-digest (%safe-file-sha256 transcript-path)
     :asciicast-path asciicast-path
     :report-path report-path
     :score (mtss-score row)
     :pass-p (mtss-pass-p row))))

(defun scorecard->replay-verdict (scorecard manifest)
  (declare (type mcp-tui-scorecard-result scorecard)
           (type runner-evidence-manifest manifest)
           (optimize (safety 3)))
  (let* ((rows (mapcar (lambda (row) (scenario-score->bundle-row row manifest))
                       (mtsr-scenario-scores scorecard)))
         (command *mcp-tui-deterministic-command*))
    (make-mcp-tui-replay-verdict
     :pass-p (and (mtsr-pass-p scorecard)
                  (mtsr-command-match-p scorecard)
                  (null (mtsr-missing-scenarios scorecard)))
     :command-match-p (mtsr-command-match-p scorecard)
     :command-fingerprint (command-fingerprint command)
     :deterministic-command command
     :bundle-rows rows
     :missing-scenarios (mtsr-missing-scenarios scorecard)
     :detail (format nil "command_ok=~A missing=~D"
                     (mtsr-command-match-p scorecard)
                     (length (mtsr-missing-scenarios scorecard)))
     :timestamp (get-universal-time))))

(defun evaluate-mcp-tui-replay-verdict (artifacts-dir command)
  (declare (type string artifacts-dir command))
  (let* ((scorecard (evaluate-mcp-tui-scorecard-gate artifacts-dir command))
         (manifest (compile-mcp-tui-evidence-manifest artifacts-dir command)))
    (scorecard->replay-verdict scorecard manifest)))

(defun mcp-tui-replay-verdict->json (verdict)
  (declare (type mcp-tui-replay-verdict verdict))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"command_match\":~A,\"command_fingerprint\":~D,\"deterministic_command\":\"~A\",\"row_count\":~D,\"missing\":~D,\"detail\":\"~A\",\"timestamp\":~D,\"rows\":["
            (if (mtrv-pass-p verdict) "true" "false")
            (if (mtrv-command-match-p verdict) "true" "false")
            (mtrv-command-fingerprint verdict)
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
                       "{\"id\":\"~A\",\"score\":~D,\"pass\":~A,\"shot\":\"~A\",\"transcript\":\"~A\",\"transcript_digest\":\"~A\",\"cast\":\"~A\",\"report\":\"~A\"}"
                       (mtbr-scenario-id row)
                       (mtbr-score row)
                       (if (mtbr-pass-p row) "true" "false")
                       (mtbr-screenshot-path row)
                       (mtbr-transcript-path row)
                       (mtbr-transcript-digest row)
                       (mtbr-asciicast-path row)
                       (mtbr-report-path row))))
    (write-string "]}" out)))
