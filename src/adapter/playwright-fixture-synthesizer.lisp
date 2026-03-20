;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-fixture-synthesizer.lisp — deterministic S1-S6 evidence fixture generator
;;; Bead: agent-orrery-j65d

(in-package #:orrery/adapter)

(defstruct (playwright-fixture-generation-result (:conc-name pfgr-))
  (pass-p nil :type boolean)
  (output-dir "" :type string)
  (generated-files 0 :type integer)
  (mode :complete :type keyword)
  (detail "" :type string))

(declaim
 (ftype (function (string string keyword) (values string &optional))
        playwright-scenario-artifact-path)
 (ftype (function (string keyword) (values playwright-fixture-generation-result &optional))
        generate-playwright-fixture-set)
 (ftype (function (playwright-fixture-generation-result) (values string &optional))
        playwright-fixture-generation-result->json))

(defun playwright-scenario-artifact-path (root sid kind)
  (declare (type string root sid)
           (type keyword kind))
  (namestring
   (merge-pathnames
    (format nil "~A-~A.~A"
            sid
            (string-downcase (symbol-name kind))
            (case kind
              (:screenshot "png")
              (:trace "zip")
              (:transcript "txt")
              (otherwise "json")))
    (pathname root))))

(defun %write-playwright-fixture-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s))
  t)

(defun generate-playwright-fixture-set (output-dir mode)
  "MODE can be :complete or :gapped.
:complete writes S1-S6 screenshot/trace/transcript/report fixtures.
:gapped omits trace for S6 to force fail-closed path." 
  (declare (type string output-dir)
           (type keyword mode)
           (optimize (safety 3)))
  (ensure-directories-exist (merge-pathnames "dummy" output-dir))
  (let ((count 0))
    (%write-playwright-fixture-file
     (merge-pathnames "playwright-report.json" (pathname output-dir))
     "fixture report")
    (incf count)
    (dolist (sid *playwright-required-scenarios*)
      (dolist (kind '(:screenshot :trace :transcript))
        (unless (and (eq mode :gapped)
                     (string= sid "S6")
                     (eq kind :trace))
          (%write-playwright-fixture-file
           (playwright-scenario-artifact-path output-dir sid kind)
           (format nil "fixture ~A ~A" sid kind))
          (incf count))))
    (make-playwright-fixture-generation-result
     :pass-p t
     :output-dir output-dir
     :generated-files count
     :mode mode
     :detail (format nil "mode=~A generated=~D" mode count))))

(defun playwright-fixture-generation-result->json (result)
  (declare (type playwright-fixture-generation-result result))
  (format nil
          "{\"pass\":~A,\"output_dir\":\"~A\",\"generated_files\":~D,\"mode\":\"~A\",\"detail\":\"~A\"}"
          (if (pfgr-pass-p result) "true" "false")
          (pfgr-output-dir result)
          (pfgr-generated-files result)
          (string-downcase (symbol-name (pfgr-mode result)))
          (pfgr-detail result)))
