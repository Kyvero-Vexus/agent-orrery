;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-witness-exporter.lisp — deterministic T1-T6 witness bundle exporter
;;; Bead: agent-orrery-s164

(in-package #:orrery/adapter)

(defstruct (mcp-tui-witness-bundle (:conc-name mtwb-))
  (pass-p nil :type boolean)
  (deterministic-command "" :type string)
  (command-match-p nil :type boolean)
  (command-fingerprint 0 :type integer)
  (scenario-count 0 :type integer)
  (missing-scenarios nil :type list)
  (transcript-digest-map nil :type list)
  (closure-pass-p nil :type boolean)
  (signature "" :type string)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (runner-evidence-manifest) (values list &optional)) manifest-transcript-digest-map)
 (ftype (function (string string) (values mcp-tui-witness-bundle &optional))
        evaluate-mcp-tui-witness-bundle)
 (ftype (function (string string string) (values mcp-tui-witness-bundle &optional))
        write-mcp-tui-witness-bundle)
 (ftype (function (mcp-tui-witness-bundle) (values string &optional))
        mcp-tui-witness-bundle->json))

(defun manifest-transcript-digest-map (manifest)
  (declare (type runner-evidence-manifest manifest))
  (let ((rows nil))
    (dolist (artifact (rem-artifacts manifest) (nreverse rows))
      (when (and (eq :transcript (ea-artifact-kind artifact))
                 (ea-present-p artifact))
        (push (cons (normalize-scenario-id (ea-scenario-id artifact))
                    (file-sha256 (ea-path artifact)))
              rows)))))

(defun %witness-signature (command-fingerprint transcript-digest-map closure-pass-p)
  (declare (type integer command-fingerprint)
           (type list transcript-digest-map)
           (type boolean closure-pass-p))
  (let* ((payload (with-output-to-string (out)
                    (format out "~D|~A|" command-fingerprint (if closure-pass-p "1" "0"))
                    (dolist (pair transcript-digest-map)
                      (format out "~A=~A;" (car pair) (cdr pair)))))
         (fingerprint (sxhash payload)))
    (format nil "witness-~36R" (abs fingerprint))))

(defun %manifest-missing-required-scenarios (manifest)
  (declare (type runner-evidence-manifest manifest))
  (let ((present-ids (mapcar (lambda (row)
                               (normalize-scenario-id (sce-scenario-id row)))
                             (rem-scenarios manifest))))
    (remove-if (lambda (sid) (member sid present-ids :test #'string=))
               *mcp-tui-required-scenarios*)))

(defun evaluate-mcp-tui-witness-bundle (artifacts-dir command)
  (declare (type string artifacts-dir command))
  (let* ((manifest (compile-mcp-tui-evidence-manifest artifacts-dir command))
         (closure (evaluate-mcp-tui-closure-adapter artifacts-dir command))
         (transcript-map (manifest-transcript-digest-map manifest))
         (missing (%manifest-missing-required-scenarios manifest))
         (command-match (string= command *mcp-tui-deterministic-command*))
         (closure-pass (tcr-pass-p closure))
         (pass (and command-match closure-pass (null missing)))
         (command-fingerprint (command-fingerprint command))
         (signature (%witness-signature command-fingerprint transcript-map closure-pass)))
    (make-mcp-tui-witness-bundle
     :pass-p pass
     :deterministic-command *mcp-tui-deterministic-command*
     :command-match-p command-match
     :command-fingerprint command-fingerprint
     :scenario-count (length *mcp-tui-required-scenarios*)
     :missing-scenarios missing
     :transcript-digest-map transcript-map
     :closure-pass-p closure-pass
     :signature signature
     :detail (format nil "command_ok=~A closure_ok=~A missing=~D"
                     command-match closure-pass (length missing))
     :timestamp (get-universal-time))))

(defun mcp-tui-witness-bundle->json (bundle)
  (declare (type mcp-tui-witness-bundle bundle))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"deterministic_command\":\"~A\",\"command_match\":~A,\"command_fingerprint\":~D,\"scenario_count\":~D,\"missing\":~D,\"closure_pass\":~A,\"signature\":\"~A\",\"detail\":\"~A\",\"timestamp\":~D,\"missing_scenarios\":["
            (if (mtwb-pass-p bundle) "true" "false")
            (mtwb-deterministic-command bundle)
            (if (mtwb-command-match-p bundle) "true" "false")
            (mtwb-command-fingerprint bundle)
            (mtwb-scenario-count bundle)
            (length (mtwb-missing-scenarios bundle))
            (if (mtwb-closure-pass-p bundle) "true" "false")
            (mtwb-signature bundle)
            (mtwb-detail bundle)
            (mtwb-timestamp bundle))
    (loop for sid in (mtwb-missing-scenarios bundle)
          for idx from 0
          do (progn
               (when (> idx 0) (write-string "," out))
               (format out "\"~A\"" sid)))
    (write-string "],\"transcript_digests\":[" out)
    (loop for pair in (mtwb-transcript-digest-map bundle)
          for idx from 0
          do (progn
               (when (> idx 0) (write-string "," out))
               (format out "{\"scenario\":\"~A\",\"digest\":\"~A\"}"
                       (car pair) (cdr pair))))
    (write-string "]}" out)))

(defun write-mcp-tui-witness-bundle (artifacts-dir command output-path)
  (declare (type string artifacts-dir command output-path))
  (let ((bundle (evaluate-mcp-tui-witness-bundle artifacts-dir command)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string (mcp-tui-witness-bundle->json bundle) s))
    bundle))
