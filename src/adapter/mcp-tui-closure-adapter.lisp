;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-closure-adapter.lisp — Epic 3 scorecard-to-closure adapter
;;; Bead: agent-orrery-5bgp

(in-package #:orrery/adapter)

(defstruct (tui-closure-gap (:conc-name tcg-))
  (scenario-id "" :type string)
  (missing-kinds nil :type list)
  (score 0 :type integer))

(defstruct (tui-closure-report (:conc-name tcr-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (deterministic-command "" :type string)
  (gaps nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (mcp-tui-scenario-score) (values tui-closure-gap &optional))
        scenario-score->closure-gap)
 (ftype (function (list) (values string &optional))
        tcg-missing-kinds->json-array)
 (ftype (function (mcp-tui-scorecard-result) (values tui-closure-report &optional))
        scorecard->closure-report)
 (ftype (function (string string) (values tui-closure-report &optional))
        evaluate-mcp-tui-closure-adapter)
 (ftype (function (tui-closure-report) (values string &optional))
        tui-closure-report->json))

(defun scenario-score->closure-gap (row)
  (declare (type mcp-tui-scenario-score row))
  (let ((missing nil))
    (unless (mtss-screenshot-p row) (push :screenshot missing))
    (unless (mtss-transcript-p row) (push :transcript missing))
    (unless (mtss-asciicast-p row) (push :asciicast missing))
    (unless (mtss-report-p row) (push :machine-report missing))
    (make-tui-closure-gap
     :scenario-id (mtss-scenario-id row)
     :missing-kinds (nreverse missing)
     :score (mtss-score row))))

(defun tcg-missing-kinds->json-array (missing-kinds)
  (declare (type list missing-kinds))
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for kind in missing-kinds
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~A\"" (%json-escape (string-downcase (symbol-name kind))))))
    (write-string "]" out)))

(defun scorecard->closure-report (scorecard)
  (declare (type mcp-tui-scorecard-result scorecard)
           (optimize (safety 3)))
  (let ((gaps nil))
    (dolist (row (mtsr-scenario-scores scorecard))
      (unless (mtss-pass-p row)
        (push (scenario-score->closure-gap row) gaps)))
    (let* ((gap-list (nreverse gaps))
           (pass (and (mtsr-pass-p scorecard)
                      (mtsr-command-match-p scorecard)
                      (null gap-list))))
      (make-tui-closure-report
       :pass-p pass
       :command-match-p (mtsr-command-match-p scorecard)
       :deterministic-command *mcp-tui-deterministic-command*
       :gaps gap-list
       :detail (format nil "command_ok=~A gap_count=~D scenario_rows=~D"
                       (mtsr-command-match-p scorecard)
                       (length gap-list)
                       (length (mtsr-scenario-scores scorecard)))
       :timestamp (get-universal-time)))))

(defun evaluate-mcp-tui-closure-adapter (artifacts-dir command)
  (declare (type string artifacts-dir command))
  (scorecard->closure-report
   (evaluate-mcp-tui-scorecard-gate artifacts-dir command)))

(defun tui-closure-report->json (report)
  (declare (type tui-closure-report report))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"command_match\":~A,\"required_runner\":\"mcp-tui-driver\",\"deterministic_command\":\"~A\",\"gap_count\":~D,\"detail\":\"~A\",\"timestamp\":~D,\"gaps\":["
            (if (tcr-pass-p report) "true" "false")
            (if (tcr-command-match-p report) "true" "false")
            (%json-escape *mcp-tui-deterministic-command*)
            (length (tcr-gaps report))
            (%json-escape (tcr-detail report))
            (tcr-timestamp report))
    (loop for g in (tcr-gaps report)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out
                       "{\"id\":\"~A\",\"score\":~D,\"missing_count\":~D,\"missing_kinds\":~A}"
                       (%json-escape (tcg-scenario-id g))
                       (tcg-score g)
                       (length (tcg-missing-kinds g))
                       (tcg-missing-kinds->json-array (tcg-missing-kinds g)))))
    (write-string "]}" out)))
