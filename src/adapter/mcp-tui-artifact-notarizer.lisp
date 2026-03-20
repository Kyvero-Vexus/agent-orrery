;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-artifact-notarizer.lisp — typed T1-T6 notarizer with env fingerprint + drift diff
;;; Bead: agent-orrery-l71w

(in-package #:orrery/adapter)

(defparameter *mcp-tui-notary-env-keys*
  '("CI" "GITHUB_ACTIONS" "GITLAB_CI" "SBCL_HOME" "USER"))

(defstruct (mcp-tui-artifact-notarization (:conc-name mtan-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (command-fingerprint 0 :type integer)
  (environment-fingerprint 0 :type integer)
  (scenario-count 0 :type integer)
  (missing-scenarios nil :type list)
  (drift-pass-p nil :type boolean)
  (drift-mismatch-count 0 :type integer)
  (drift-detail "" :type string)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (list) (values integer &optional)) mcp-tui-environment-fingerprint)
 (ftype (function (string string string) (values mcp-tui-artifact-notarization &optional))
        notarize-mcp-tui-artifacts)
 (ftype (function (string string string string) (values mcp-tui-artifact-notarization &optional))
        write-mcp-tui-artifact-notarization)
 (ftype (function (mcp-tui-artifact-notarization) (values string &optional))
        mcp-tui-artifact-notarization->json))

(defun mcp-tui-environment-fingerprint (env-keys)
  (declare (type list env-keys))
  (let ((acc 0))
    (dolist (k env-keys)
      (let* ((key (if (stringp k) k (princ-to-string k)))
             (value (or (uiop:getenv key) ""))
             (line (format nil "~A=~A" key value)))
        (setf acc (sxhash (format nil "~D|~A" acc line)))))
    acc))

(defun notarize-mcp-tui-artifacts (artifacts-dir command baseline-dir)
  (declare (type string artifacts-dir command baseline-dir))
  (let* ((scorecard (evaluate-mcp-tui-scorecard-gate artifacts-dir command))
         (drift (compare-tui-artifact-bundles baseline-dir artifacts-dir))
         (missing (mtsr-missing-scenarios scorecard))
         (command-ok (mtsr-command-match-p scorecard))
         (drift-ok (tdr-pass-p drift))
         (pass (and (mtsr-pass-p scorecard)
                    command-ok
                    (null missing)
                    drift-ok)))
    (make-mcp-tui-artifact-notarization
     :pass-p pass
     :command-match-p command-ok
     :command-fingerprint (command-fingerprint command)
     :environment-fingerprint (mcp-tui-environment-fingerprint *mcp-tui-notary-env-keys*)
     :scenario-count (length *default-tui-scenarios*)
     :missing-scenarios missing
     :drift-pass-p drift-ok
     :drift-mismatch-count (tdr-mismatch-count drift)
     :drift-detail (tdr-detail drift)
     :detail (format nil "command_ok=~A missing=~D drift_ok=~A drift=~A"
                     command-ok (length missing) drift-ok (tdr-detail drift))
     :timestamp (get-universal-time))))

(defun write-mcp-tui-artifact-notarization (artifacts-dir command baseline-dir output-path)
  (declare (type string artifacts-dir command baseline-dir output-path))
  (let ((note (notarize-mcp-tui-artifacts artifacts-dir command baseline-dir)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string (mcp-tui-artifact-notarization->json note) s))
    note))

(defun mcp-tui-artifact-notarization->json (note)
  (declare (type mcp-tui-artifact-notarization note))
  (format nil
          "{\"pass\":~A,\"command_match\":~A,\"command_fingerprint\":~D,\"environment_fingerprint\":~D,\"scenario_count\":~D,\"missing_count\":~D,\"drift_pass\":~A,\"drift_mismatch_count\":~D,\"drift_detail\":\"~A\",\"detail\":\"~A\",\"timestamp\":~D}"
          (if (mtan-pass-p note) "true" "false")
          (if (mtan-command-match-p note) "true" "false")
          (mtan-command-fingerprint note)
          (mtan-environment-fingerprint note)
          (mtan-scenario-count note)
          (length (mtan-missing-scenarios note))
          (if (mtan-drift-pass-p note) "true" "false")
          (mtan-drift-mismatch-count note)
          (mtan-drift-detail note)
          (mtan-detail note)
          (mtan-timestamp note)))
