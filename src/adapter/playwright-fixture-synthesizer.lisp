;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-fixture-synthesizer.lisp — deterministic S1-S6 evidence fixture generator
;;; Bead: agent-orrery-defb

(in-package #:orrery/adapter)

(defstruct (playwright-fixture-generation-result (:conc-name pfgr-))
  (pass-p nil :type boolean)
  (output-dir "" :type string)
  (generated-files 0 :type integer)
  (mode :complete :type keyword)
  (deterministic-command "" :type string)
  (command-transcript-path "" :type string)
  (detail "" :type string))

(declaim
 (ftype (function (string string keyword) (values string &optional))
        playwright-scenario-artifact-path)
 (ftype (function (string) (values string &optional))
        playwright-command-transcript-path)
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

(defun playwright-command-transcript-path (root)
  (declare (type string root)
           (optimize (safety 3)))
  (namestring
   (merge-pathnames "playwright-command-transcript.json" (pathname root))))

(defun %write-playwright-fixture-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s))
  t)

(defun %reset-playwright-fixture-output-dir (output-dir)
  (declare (type string output-dir)
           (optimize (safety 3)))
  (let ((dir (uiop:ensure-directory-pathname output-dir)))
    (when (and (> (length output-dir) 8)
               (probe-file dir))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))
    (ensure-directories-exist (merge-pathnames "dummy" dir))))

(defun %scenario-enabled-p (sid mode)
  (declare (type string sid)
           (type keyword mode)
           (optimize (safety 3)))
  (not (and (eq mode :missing-scenario)
            (string= sid "S6"))))

(defun %artifact-enabled-p (sid kind mode)
  (declare (type string sid)
           (type keyword kind mode)
           (optimize (safety 3)))
  (not (and (eq mode :missing-trace)
            (string= sid "S6")
            (eq kind :trace))))

(defun %mode-label (mode)
  (declare (type keyword mode)
           (optimize (safety 3)))
  (case mode
    (:gapped :missing-trace)
    (otherwise mode)))

(defun generate-playwright-fixture-set (output-dir mode)
  "MODE can be :complete, :missing-scenario, :missing-trace (or legacy alias :gapped).
Writes deterministic Playwright S1-S6 artifacts plus command transcript metadata
consumed by unified preflight bundle checks."
  (declare (type string output-dir)
           (type keyword mode)
           (optimize (safety 3)))
  (%reset-playwright-fixture-output-dir output-dir)
  (let* ((normalized-mode (%mode-label mode))
         (deterministic-command *playwright-deterministic-command*)
         (count 0))
    (%write-playwright-fixture-file
     (merge-pathnames "playwright-report.json" (pathname output-dir))
     "fixture report")
    (incf count)
    (dolist (sid *playwright-required-scenarios*)
      (when (%scenario-enabled-p sid normalized-mode)
        (dolist (kind '(:screenshot :trace :transcript))
          (when (%artifact-enabled-p sid kind normalized-mode)
            (%write-playwright-fixture-file
             (playwright-scenario-artifact-path output-dir sid kind)
             (format nil "fixture ~A ~A" sid kind))
            (incf count)))))
    (%write-playwright-fixture-file
     (playwright-command-transcript-path output-dir)
     (format nil
             "{\"framework\":\"playwright\",\"scenarios\":\"S1-S6\",\"deterministic_command\":\"~A\",\"transcript_hash\":\"fixture-transcript-sha256\"}"
             deterministic-command))
    (incf count)
    (make-playwright-fixture-generation-result
     :pass-p t
     :output-dir output-dir
     :generated-files count
     :mode normalized-mode
     :deterministic-command deterministic-command
     :command-transcript-path (playwright-command-transcript-path output-dir)
     :detail (format nil "mode=~A generated=~D" normalized-mode count))))

(defun playwright-fixture-generation-result->json (result)
  (declare (type playwright-fixture-generation-result result))
  (format nil
          "{\"pass\":~A,\"output_dir\":\"~A\",\"generated_files\":~D,\"mode\":\"~A\",\"deterministic_command\":\"~A\",\"command_transcript_path\":\"~A\",\"detail\":\"~A\"}"
          (if (pfgr-pass-p result) "true" "false")
          (pfgr-output-dir result)
          (pfgr-generated-files result)
          (string-downcase (symbol-name (pfgr-mode result)))
          (pfgr-deterministic-command result)
          (pfgr-command-transcript-path result)
          (pfgr-detail result)))
