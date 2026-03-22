;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-lineage-stamp.lisp — Epic 3 deterministic T1-T6 lineage stamp
;;; Bead: agent-orrery-fnpn

(in-package #:orrery/adapter)

(defstruct (mcp-tui-rerun-card (:conc-name mtrc-))
  (scenario-id "" :type string)
  (command "" :type string)
  (command-hash 0 :type integer)
  (transcript-path "" :type string)
  (screenshot-path "" :type string)
  (asciicast-path "" :type string)
  (report-path "" :type string)
  (ready-p nil :type boolean))

(defstruct (mcp-tui-lineage-stamp (:conc-name mtls-))
  (pass-p nil :type boolean)
  (required-runner "mcp-tui-driver" :type string)
  (deterministic-command "" :type string)
  (command-match-p nil :type boolean)
  (command-hash 0 :type integer)
  (transcript-chain-digest "" :type string)
  (artifact-checksum-map nil :type list)
  (rerun-cards nil :type list)
  (missing-scenarios nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (runner-evidence-manifest evidence-artifact-kind) (values list &optional))
        manifest-artifact-digest-map)
 (ftype (function (list) (values string &optional)) lineage-digest-from-map)
 (ftype (function (string string) (values mcp-tui-rerun-card &optional))
        build-mcp-tui-rerun-card)
 (ftype (function (string string) (values list &optional))
        build-mcp-tui-rerun-cards)
 (ftype (function (string string) (values mcp-tui-lineage-stamp &optional))
        evaluate-mcp-tui-lineage-stamp)
 (ftype (function (mcp-tui-lineage-stamp) (values string &optional))
        mcp-tui-lineage-stamp->json))

(defun manifest-artifact-digest-map (manifest kind)
  (declare (type runner-evidence-manifest manifest)
           (type evidence-artifact-kind kind)
           (optimize (safety 3)))
  (let ((rows nil))
    (dolist (artifact (rem-artifacts manifest) (sort rows #'string< :key #'car))
      (when (and (eq kind (ea-artifact-kind artifact))
                 (ea-present-p artifact)
                 (not (string= "" (ea-scenario-id artifact))))
        (push (cons (normalize-scenario-id (ea-scenario-id artifact))
                    (file-sha256 (ea-path artifact)))
              rows)))))

(defun lineage-digest-from-map (entries)
  (declare (type list entries)
           (optimize (safety 3)))
  (let ((payload (with-output-to-string (out)
                   (dolist (pair (sort (copy-list entries) #'string< :key #'car))
                     (format out "~A=~A;" (car pair) (cdr pair))))))
    (format nil "lineage-~36R" (abs (sxhash payload)))))

(defun %scenario-missing-list (manifest)
  (declare (type runner-evidence-manifest manifest))
  (let ((missing nil))
    (dolist (sid *mcp-tui-required-scenarios* (nreverse missing))
      (let ((row (find sid (rem-scenarios manifest) :test #'string= :key #'sce-scenario-id)))
        (unless (and row (eq :pass (sce-status row)))
          (push sid missing))))))

(defun build-mcp-tui-rerun-card (artifacts-dir scenario-id)
  (declare (type string artifacts-dir scenario-id)
           (optimize (safety 3)))
  (let* ((command *mcp-tui-deterministic-command*)
         (transcript (merge-pathnames (format nil "~A-transcript.txt" scenario-id) artifacts-dir))
         (shot (merge-pathnames (format nil "~A-shot.png" scenario-id) artifacts-dir))
         (cast (merge-pathnames (format nil "~A-asciicast.cast" scenario-id) artifacts-dir))
         (report (merge-pathnames (format nil "~A-report.json" scenario-id) artifacts-dir))
         (ready (and (probe-file transcript) (probe-file shot) (probe-file cast) (probe-file report))))
    (make-mcp-tui-rerun-card
     :scenario-id scenario-id
     :command command
     :command-hash (command-fingerprint command)
     :transcript-path (namestring transcript)
     :screenshot-path (namestring shot)
     :asciicast-path (namestring cast)
     :report-path (namestring report)
     :ready-p (not (null ready)))))

(defun build-mcp-tui-rerun-cards (artifacts-dir command)
  (declare (type string artifacts-dir command)
           (ignore command)
           (optimize (safety 3)))
  (mapcar (lambda (sid) (build-mcp-tui-rerun-card artifacts-dir sid))
          *mcp-tui-required-scenarios*))

(defun evaluate-mcp-tui-lineage-stamp (artifacts-dir command)
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((manifest (compile-mcp-tui-evidence-manifest artifacts-dir command))
         (command-match (string= command *mcp-tui-deterministic-command*))
         (missing (%scenario-missing-list manifest))
         (transcript-map (manifest-artifact-digest-map manifest :transcript))
         (shot-map (manifest-artifact-digest-map manifest :screenshot))
         (cast-map (manifest-artifact-digest-map manifest :asciicast))
         (report-map (manifest-artifact-digest-map manifest :machine-report))
         (artifact-map (list (cons :transcript transcript-map)
                             (cons :screenshot shot-map)
                             (cons :asciicast cast-map)
                             (cons :machine-report report-map)))
         (rerun-cards (build-mcp-tui-rerun-cards artifacts-dir command))
         (lineage (lineage-digest-from-map transcript-map))
         (pass (and command-match
                    (null missing)
                    (= (length transcript-map) (length *mcp-tui-required-scenarios*)))))
    (make-mcp-tui-lineage-stamp
     :pass-p pass
     :required-runner "mcp-tui-driver"
     :deterministic-command *mcp-tui-deterministic-command*
     :command-match-p command-match
     :command-hash (command-fingerprint command)
     :transcript-chain-digest lineage
     :artifact-checksum-map artifact-map
     :rerun-cards rerun-cards
     :missing-scenarios missing
     :detail (format nil "command_ok=~A missing=~D transcripts=~D"
                     command-match (length missing) (length transcript-map))
     :timestamp (get-universal-time))))

(defun %emit-digest-rows-json (rows)
  (declare (type list rows))
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for pair in rows
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "{\"scenario\":\"~A\",\"digest\":\"~A\"}" (car pair) (cdr pair))))
    (write-string "]" out)))

(defun %emit-rerun-cards-json (cards)
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for card in cards
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out
                       "{\"scenario\":\"~A\",\"command\":\"~A\",\"command_hash\":~D,\"transcript\":\"~A\",\"screenshot\":\"~A\",\"asciicast\":\"~A\",\"report\":\"~A\",\"ready\":~A}"
                       (mtrc-scenario-id card)
                       (mtrc-command card)
                       (mtrc-command-hash card)
                       (mtrc-transcript-path card)
                       (mtrc-screenshot-path card)
                       (mtrc-asciicast-path card)
                       (mtrc-report-path card)
                       (if (mtrc-ready-p card) "true" "false"))))
    (write-string "]" out)))

(defun mcp-tui-lineage-stamp->json (stamp)
  (declare (type mcp-tui-lineage-stamp stamp)
           (optimize (safety 3)))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"required_runner\":\"~A\",\"deterministic_command\":\"~A\",\"command_match\":~A,\"command_hash\":~D,\"transcript_chain_digest\":\"~A\",\"missing_scenarios\":["
            (if (mtls-pass-p stamp) "true" "false")
            (mtls-required-runner stamp)
            (mtls-deterministic-command stamp)
            (if (mtls-command-match-p stamp) "true" "false")
            (mtls-command-hash stamp)
            (mtls-transcript-chain-digest stamp))
    (loop for sid in (mtls-missing-scenarios stamp)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~A\"" sid)))
    (write-string "],\"artifact_checksums\":{" out)
    (loop for (kind . rows) in (mtls-artifact-checksum-map stamp)
          for i from 0
          do (progn
               (when (> i 0) (write-string "," out))
               (format out "\"~(~A~)\":~A" kind (%emit-digest-rows-json rows))))
    (format out
            "},\"rerun_cards\":~A,\"detail\":\"~A\",\"timestamp\":~D}"
            (%emit-rerun-cards-json (mtls-rerun-cards stamp))
            (mtls-detail stamp)
            (mtls-timestamp stamp))))
