;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-fixture-generator.lisp — deterministic T1-T6 evidence fixture generator
;;; Bead: agent-orrery-17bl

(in-package #:orrery/adapter)

(defstruct (tui-fixture-generation-result (:conc-name tfgr-))
  (pass-p nil :type boolean)
  (output-dir "" :type string)
  (generated-files 0 :type integer)
  (mode :complete :type keyword)
  (detail "" :type string))

(declaim
 (ftype (function (string string keyword) (values string &optional))
        scenario-artifact-path)
 (ftype (function (string keyword) (values tui-fixture-generation-result &optional))
        generate-tui-fixture-set)
 (ftype (function (tui-fixture-generation-result) (values string &optional))
        tui-fixture-generation-result->json))

(defun scenario-artifact-path (root sid kind)
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

(defun %write-fixture-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s))
  t)

(defun generate-tui-fixture-set (output-dir mode)
  "MODE can be :complete or :gapped.
:complete writes T1-T6 screenshot/transcript/asciicast/report fixtures.
:gapped omits asciicast for T6 to force fail-closed path." 
  (declare (type string output-dir)
           (type keyword mode)
           (optimize (safety 3)))
  (ensure-directories-exist (merge-pathnames "dummy" output-dir))
  (let ((count 0))
    (dolist (sid *mcp-tui-required-scenarios*)
      (dolist (kind '(:screenshot :transcript :asciicast :report))
        (unless (and (eq mode :gapped)
                     (string= sid "T6")
                     (eq kind :asciicast))
          (%write-fixture-file (scenario-artifact-path output-dir sid kind)
                               (format nil "fixture ~A ~A" sid kind))
          (incf count))))
    (make-tui-fixture-generation-result
     :pass-p t
     :output-dir output-dir
     :generated-files count
     :mode mode
     :detail (format nil "mode=~A generated=~D" mode count))))

(defun tui-fixture-generation-result->json (result)
  (declare (type tui-fixture-generation-result result))
  (format nil
          "{\"pass\":~A,\"output_dir\":\"~A\",\"generated_files\":~D,\"mode\":\"~A\",\"detail\":\"~A\"}"
          (if (tfgr-pass-p result) "true" "false")
          (tfgr-output-dir result)
          (tfgr-generated-files result)
          (string-downcase (symbol-name (tfgr-mode result)))
          (tfgr-detail result)))
