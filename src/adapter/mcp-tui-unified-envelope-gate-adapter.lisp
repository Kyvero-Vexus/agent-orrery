;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-unified-envelope-gate-adapter.lisp — gate-input projection from unified envelope
;;; Bead: agent-orrery-i1x1

(in-package #:orrery/adapter)

(defstruct (mcp-tui-gate-input-row (:conc-name mtgir-)
            (:constructor make-mcp-tui-gate-input-row (&key scenario-id blocking-p taxonomy-codes command-hash detail)))
  (scenario-id "" :type string)
  (blocking-p nil :type boolean)
  (taxonomy-codes '() :type list)
  (command-hash 0 :type integer)
  (detail "" :type string))

(defstruct (mcp-tui-gate-adapter-result (:conc-name mtgar-)
            (:constructor make-mcp-tui-gate-adapter-result (&key pass-p deterministic-command rows detail timestamp)))
  (pass-p nil :type boolean)
  (deterministic-command "" :type string)
  (rows '() :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (mcp-tui-envelope-row) (values mcp-tui-gate-input-row &optional)) envelope-row->gate-row)
 (ftype (function (mcp-tui-envelope-report) (values mcp-tui-gate-adapter-result &optional))
        project-unified-envelope->gate-input)
 (ftype (function (string string) (values mcp-tui-gate-adapter-result &optional))
        evaluate-mcp-tui-unified-envelope-gate-adapter)
 (ftype (function (mcp-tui-gate-adapter-result) (values string &optional))
        mcp-tui-gate-adapter-result->json))

(defun envelope-row->gate-row (row)
  (declare (type mcp-tui-envelope-row row)
           (optimize (safety 3)))
  (make-mcp-tui-gate-input-row
   :scenario-id (mter-scenario-id row)
   :blocking-p (or (not (mter-pass-p row))
                   (plusp (length (mter-taxonomy-codes row))))
   :taxonomy-codes (mter-taxonomy-codes row)
   :command-hash (mter-command-hash row)
   :detail (mter-detail row)))

(defun project-unified-envelope->gate-input (report)
  (declare (type mcp-tui-envelope-report report)
           (optimize (safety 3)))
  (let ((rows (mapcar #'envelope-row->gate-row (mtep-rows report))))
    (make-mcp-tui-gate-adapter-result
     :pass-p (and (mtep-pass-p report)
                  (every (lambda (r) (not (mtgir-blocking-p r))) rows))
     :deterministic-command *mcp-tui-deterministic-command*
     :rows rows
     :detail (if (mtep-pass-p report)
                 "Gate adapter passed: no blocking taxonomy codes."
                 "Gate adapter failed: blocking taxonomy present.")
     :timestamp (mtep-timestamp report))))

(defun evaluate-mcp-tui-unified-envelope-gate-adapter (artifacts-dir command)
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (project-unified-envelope->gate-input
   (project-mcp-tui-unified-envelope artifacts-dir command)))

(defun mcp-tui-gate-adapter-result->json (result)
  (declare (type mcp-tui-gate-adapter-result result)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (format s "{\"pass\":~A,\"deterministic_command\":\"~A\",\"rows\":["
            (if (mtgar-pass-p result) "true" "false")
            (mtgar-deterministic-command result))
    (loop for row in (mtgar-rows result)
          for i from 0 do
            (when (> i 0) (write-char #\, s))
            (format s "{\"scenario_id\":\"~A\",\"blocking\":~A,\"command_hash\":~D,\"taxonomy_codes\":["
                    (mtgir-scenario-id row)
                    (if (mtgir-blocking-p row) "true" "false")
                    (mtgir-command-hash row))
            (loop for c in (mtgir-taxonomy-codes row)
                  for j from 0 do
                    (when (> j 0) (write-char #\, s))
                    (format s "\"~(~A~)\"" c))
            (format s "],\"detail\":\"~A\"}" (mtgir-detail row)))
    (format s "],\"detail\":\"~A\",\"timestamp\":~D}"
            (mtgar-detail result)
            (mtgar-timestamp result))))
