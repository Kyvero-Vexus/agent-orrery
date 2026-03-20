;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-command-pack.lisp — deterministic T1-T6 command/artifact contract pack
;;; Bead: agent-orrery-tojz

(in-package #:orrery/adapter)

(defstruct (mcp-tui-command-row (:conc-name mtcr-))
  (scenario-id "" :type string)
  (command "" :type string)
  (screenshot-path "" :type string)
  (transcript-path "" :type string)
  (asciicast-path "" :type string)
  (report-path "" :type string))

(defstruct (mcp-tui-command-pack (:conc-name mtcp-))
  (pass-p nil :type boolean)
  (deterministic-command "" :type string)
  (rows nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string keyword) (values string &optional)) mcp-tui-artifact-path)
 (ftype (function (string) (values mcp-tui-command-row &optional)) build-mcp-tui-command-row)
 (ftype (function () (values mcp-tui-command-pack &optional)) build-mcp-tui-command-pack)
 (ftype (function (mcp-tui-command-pack) (values string &optional)) mcp-tui-command-pack->json))

(defun mcp-tui-artifact-path (root sid kind)
  (declare (type string root sid)
           (type keyword kind))
  (namestring
   (merge-pathnames
    (format nil "~A-~A.~A"
            sid
            (string-downcase (symbol-name kind))
            (case kind
              (:screenshot "png")
              (:transcript "txt")
              (:asciicast "cast")
              (otherwise "json")))
    (pathname root))))

(defun build-mcp-tui-command-row (scenario-id)
  (declare (type string scenario-id))
  (let ((root "test-results/tui-artifacts/"))
    (make-mcp-tui-command-row
     :scenario-id scenario-id
     :command *mcp-tui-deterministic-command*
     :screenshot-path (mcp-tui-artifact-path root scenario-id :screenshot)
     :transcript-path (mcp-tui-artifact-path root scenario-id :transcript)
     :asciicast-path (mcp-tui-artifact-path root scenario-id :asciicast)
     :report-path (mcp-tui-artifact-path root scenario-id :report))))

(defun build-mcp-tui-command-pack ()
  (let ((rows (mapcar #'build-mcp-tui-command-row *mcp-tui-required-scenarios*)))
    (make-mcp-tui-command-pack
     :pass-p t
     :deterministic-command *mcp-tui-deterministic-command*
     :rows rows
     :detail (format nil "rows=~D" (length rows))
     :timestamp (get-universal-time))))

(defun mcp-tui-command-pack->json (pack)
  (declare (type mcp-tui-command-pack pack))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"deterministic_command\":\"~A\",\"row_count\":~D,\"detail\":\"~A\",\"timestamp\":~D,\"rows\":["
            (if (mtcp-pass-p pack) "true" "false")
            (mtcp-deterministic-command pack)
            (length (mtcp-rows pack))
            (mtcp-detail pack)
            (mtcp-timestamp pack))
    (loop for row in (mtcp-rows pack)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out
                       "{\"id\":\"~A\",\"command\":\"~A\",\"shot\":\"~A\",\"transcript\":\"~A\",\"cast\":\"~A\",\"report\":\"~A\"}"
                       (mtcr-scenario-id row)
                       (mtcr-command row)
                       (mtcr-screenshot-path row)
                       (mtcr-transcript-path row)
                       (mtcr-asciicast-path row)
                       (mtcr-report-path row))))
    (write-string "]}" out)))
