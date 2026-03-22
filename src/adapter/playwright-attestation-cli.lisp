;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-attestation-cli.lisp — deterministic S1-S6 attestation CLI report
;;; Bead: agent-orrery-cmkb

(in-package #:orrery/adapter)

(defstruct (playwright-attestation-cli-report (:conc-name pacr-))
  (pass-p nil :type boolean)
  (deterministic-command "" :type string)
  (command-match-p nil :type boolean)
  (command-fingerprint 0 :type integer)
  (scenario-count 0 :type integer)
  (missing-scenarios nil :type list)
  (attestations nil :type list)
  (transcript-digest-map nil :type list)
  (signature "" :type string)
  (timestamp 0 :type integer)
  (detail "" :type string))

(declaim
 (ftype (function (web-scenario-attestation) (values string &optional)) web-scenario-attestation->json)
 (ftype (function (string string) (values playwright-attestation-cli-report &optional))
        evaluate-playwright-attestation-cli-report)
 (ftype (function (playwright-attestation-cli-report) (values string &optional))
        playwright-attestation-cli-report->json)
 (ftype (function (string string string) (values playwright-attestation-cli-report &optional))
        write-playwright-attestation-cli-report))

(defun web-scenario-attestation->json (att)
  (declare (type web-scenario-attestation att))
  (format nil
          "{\"scenario_id\":\"~A\",\"attested\":~A,\"command_fingerprint\":~D,\"screenshot_path\":\"~A\",\"trace_path\":\"~A\",\"screenshot_sha256\":\"~A\",\"trace_sha256\":\"~A\"}"
          (wsa-scenario-id att)
          (if (wsa-attested-p att) "true" "false")
          (wsa-command-fingerprint att)
          (wsa-screenshot-path att)
          (wsa-trace-path att)
          (wsa-screenshot-hash att)
          (wsa-trace-hash att)))

(defun evaluate-playwright-attestation-cli-report (artifacts-dir command)
  (declare (type string artifacts-dir command))
  (let* ((manifest (compile-playwright-evidence-manifest artifacts-dir command))
         (attestations (mapcar (lambda (sid)
                                 (build-web-scenario-attestation manifest sid))
                               *playwright-required-scenarios*))
         (missing (loop for att in attestations
                        unless (wsa-attested-p att)
                        collect (wsa-scenario-id att)))
         (command-match (canonical-playwright-command-p command))
         (command-fingerprint (command-fingerprint command))
         (transcript-map (manifest-transcript-digest-map manifest))
         (signature (compute-web-attestation-chain attestations))
         (pass (and command-match (null missing)
                    (= (length attestations) (length *playwright-required-scenarios*)))))
    (make-playwright-attestation-cli-report
     :pass-p pass
     :deterministic-command *playwright-deterministic-command*
     :command-match-p command-match
     :command-fingerprint command-fingerprint
     :scenario-count (length attestations)
     :missing-scenarios missing
     :attestations attestations
     :transcript-digest-map transcript-map
     :signature signature
     :timestamp (get-universal-time)
     :detail (format nil "command_ok=~A missing=~D" command-match (length missing)))))

(defun %string-pair-map->json (pairs)
  (declare (type list pairs))
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for pair in pairs
          for idx from 0
          do (progn
               (when (> idx 0) (write-string "," out))
               (format out "{\"scenario\":\"~A\",\"digest\":\"~A\"}" (car pair) (cdr pair))))
    (write-string "]" out)))

(defun playwright-attestation-cli-report->json (report)
  (declare (type playwright-attestation-cli-report report))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"deterministic_command\":\"~A\",\"command_match\":~A,\"command_fingerprint\":~D,\"scenario_count\":~D,\"missing_scenarios\":["
            (if (pacr-pass-p report) "true" "false")
            (pacr-deterministic-command report)
            (if (pacr-command-match-p report) "true" "false")
            (pacr-command-fingerprint report)
            (pacr-scenario-count report))
    (loop for sid in (pacr-missing-scenarios report)
          for idx from 0
          do (progn
               (when (> idx 0) (write-string "," out))
               (format out "\"~A\"" sid)))
    (write-string "],\"attestations\":[" out)
    (loop for att in (pacr-attestations report)
          for idx from 0
          do (progn
               (when (> idx 0) (write-string "," out))
               (write-string (web-scenario-attestation->json att) out)))
    (format out
            "],\"transcript_digests\":~A,\"signature\":\"~A\",\"detail\":\"~A\",\"timestamp\":~D}"
            (%string-pair-map->json (pacr-transcript-digest-map report))
            (pacr-signature report)
            (pacr-detail report)
            (pacr-timestamp report))))

(defun write-playwright-attestation-cli-report (artifacts-dir command output-path)
  (declare (type string artifacts-dir command output-path))
  (let ((report (evaluate-playwright-attestation-cli-report artifacts-dir command)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string (playwright-attestation-cli-report->json report) s))
    report))
