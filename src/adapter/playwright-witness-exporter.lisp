;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-witness-exporter.lisp — deterministic S1-S6 witness bundle exporter
;;; Bead: agent-orrery-r9xw

(in-package #:orrery/adapter)

(defstruct (playwright-witness-bundle (:conc-name pwb-))
  (pass-p nil :type boolean)
  (deterministic-command "" :type string)
  (command-match-p nil :type boolean)
  (command-fingerprint 0 :type integer)
  (scenario-count 0 :type integer)
  (missing-scenarios nil :type list)
  (screenshot-digest-map nil :type list)
  (trace-digest-map nil :type list)
  (transcript-digest-map nil :type list)
  (closure-pass-p nil :type boolean)
  (signature "" :type string)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (runner-evidence-manifest evidence-artifact-kind) (values list &optional))
        playwright-artifact-digest-map)
 (ftype (function (string string) (values playwright-witness-bundle &optional))
        evaluate-playwright-witness-bundle)
 (ftype (function (string string string) (values playwright-witness-bundle &optional))
        write-playwright-witness-bundle)
 (ftype (function (playwright-witness-bundle) (values string &optional))
        playwright-witness-bundle->json))

(defun playwright-artifact-digest-map (manifest kind)
  (declare (type runner-evidence-manifest manifest)
           (type evidence-artifact-kind kind))
  (let ((rows nil))
    (dolist (artifact (rem-artifacts manifest) (nreverse rows))
      (when (and (eq kind (ea-artifact-kind artifact))
                 (ea-present-p artifact)
                 (> (length (ea-scenario-id artifact)) 0)
                 (probe-file (ea-path artifact)))
        (push (cons (normalize-scenario-id (ea-scenario-id artifact))
                    (file-sha256 (ea-path artifact)))
              rows)))))

(defun %playwright-missing-required-scenarios (manifest)
  (declare (type runner-evidence-manifest manifest))
  (let ((present-ids (mapcar (lambda (row)
                               (normalize-scenario-id (sce-scenario-id row)))
                             (rem-scenarios manifest))))
    (remove-if (lambda (sid) (member sid present-ids :test #'string=))
               *playwright-required-scenarios*)))

(defun %playwright-witness-signature (command-fingerprint screenshot-map trace-map transcript-map closure-pass-p)
  (declare (type integer command-fingerprint)
           (type list screenshot-map trace-map transcript-map)
           (type boolean closure-pass-p))
  (let* ((payload (with-output-to-string (out)
                    (format out "~D|~A|" command-fingerprint (if closure-pass-p "1" "0"))
                    (dolist (pair screenshot-map) (format out "shot:~A=~A;" (car pair) (cdr pair)))
                    (dolist (pair trace-map) (format out "trace:~A=~A;" (car pair) (cdr pair)))
                    (dolist (pair transcript-map) (format out "tx:~A=~A;" (car pair) (cdr pair)))))
         (fingerprint (sxhash payload)))
    (format nil "web-witness-~36R" (abs fingerprint))))

(defun evaluate-playwright-witness-bundle (artifacts-dir command)
  (declare (type string artifacts-dir command))
  (let* ((manifest (compile-playwright-evidence-manifest artifacts-dir command))
         (gate (evaluate-epic4-fail-closed-gate artifacts-dir command))
         (screenshot-map (playwright-artifact-digest-map manifest :screenshot))
         (trace-map (playwright-artifact-digest-map manifest :trace))
         (transcript-map (playwright-artifact-digest-map manifest :transcript))
         (missing (%playwright-missing-required-scenarios manifest))
         (command-match (canonical-playwright-command-p command))
         (closure-pass (e4fcr-pass-p gate))
         (pass (and command-match closure-pass (null missing)))
         (command-fingerprint (command-fingerprint command))
         (signature (%playwright-witness-signature command-fingerprint screenshot-map trace-map transcript-map closure-pass)))
    (make-playwright-witness-bundle
     :pass-p pass
     :deterministic-command *playwright-deterministic-command*
     :command-match-p command-match
     :command-fingerprint command-fingerprint
     :scenario-count (length *playwright-required-scenarios*)
     :missing-scenarios missing
     :screenshot-digest-map screenshot-map
     :trace-digest-map trace-map
     :transcript-digest-map transcript-map
     :closure-pass-p closure-pass
     :signature signature
     :detail (format nil "command_ok=~A closure_ok=~A missing=~D"
                     command-match closure-pass (length missing))
     :timestamp (get-universal-time))))

(defun %digest-map->json (map)
  (declare (type list map))
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for pair in map
          for idx from 0
          do (progn
               (when (> idx 0) (write-string "," out))
               (format out "{\"scenario\":\"~A\",\"digest\":\"~A\"}" (car pair) (cdr pair))))
    (write-string "]" out)))

(defun playwright-witness-bundle->json (bundle)
  (declare (type playwright-witness-bundle bundle))
  (format nil
          "{\"pass\":~A,\"deterministic_command\":\"~A\",\"command_match\":~A,\"command_fingerprint\":~D,\"scenario_count\":~D,\"missing\":~D,\"closure_pass\":~A,\"signature\":\"~A\",\"detail\":\"~A\",\"timestamp\":~D,\"screenshot_digests\":~A,\"trace_digests\":~A,\"transcript_digests\":~A}"
          (if (pwb-pass-p bundle) "true" "false")
          (pwb-deterministic-command bundle)
          (if (pwb-command-match-p bundle) "true" "false")
          (pwb-command-fingerprint bundle)
          (pwb-scenario-count bundle)
          (length (pwb-missing-scenarios bundle))
          (if (pwb-closure-pass-p bundle) "true" "false")
          (pwb-signature bundle)
          (pwb-detail bundle)
          (pwb-timestamp bundle)
          (%digest-map->json (pwb-screenshot-digest-map bundle))
          (%digest-map->json (pwb-trace-digest-map bundle))
          (%digest-map->json (pwb-transcript-digest-map bundle))))

(defun write-playwright-witness-bundle (artifacts-dir command output-path)
  (declare (type string artifacts-dir command output-path))
  (let ((bundle (evaluate-playwright-witness-bundle artifacts-dir command)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string (playwright-witness-bundle->json bundle) s))
    bundle))
