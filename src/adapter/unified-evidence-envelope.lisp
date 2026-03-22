;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; unified-evidence-envelope.lisp — typed unified evidence ADT + serializer
;;; Bead: agent-orrery-bag

(in-package #:orrery/adapter)

(defstruct (unified-evidence-track (:conc-name uet-)
            (:constructor make-unified-evidence-track
                (&key framework deterministic-command command-hash pass-p missing-scenarios)))
  (framework "" :type string)
  (deterministic-command "" :type string)
  (command-hash 0 :type integer)
  (pass-p nil :type boolean)
  (missing-scenarios '() :type list))

(defstruct (unified-evidence-envelope (:conc-name uee-)
            (:constructor make-unified-evidence-envelope
                (&key schema-version pass-p epic3 epic4 detail timestamp)))
  (schema-version "uee-v1" :type string)
  (pass-p nil :type boolean)
  (epic3 nil :type unified-evidence-track)
  (epic4 nil :type unified-evidence-track)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (unified-preflight-bundle) (values unified-evidence-envelope &optional))
        build-unified-evidence-envelope)
 (ftype (function (unified-evidence-envelope) (values string &optional))
        unified-evidence-envelope->json))

(defun build-unified-evidence-envelope (bundle)
  (declare (type unified-preflight-bundle bundle)
           (optimize (safety 3)))
  (let* ((play-missing (ppv-missing-scenarios (upb-web-preflight bundle)))
         (tui-missing (mtsr-missing-scenarios (upb-tui-scorecard bundle)))
         (epic4 (make-unified-evidence-track
                 :framework "playwright"
                 :deterministic-command *playwright-deterministic-command*
                 :command-hash (command-fingerprint *playwright-deterministic-command*)
                 :pass-p (ppv-pass-p (upb-web-preflight bundle))
                 :missing-scenarios play-missing))
         (epic3 (make-unified-evidence-track
                 :framework "mcp-tui-driver"
                 :deterministic-command *mcp-tui-deterministic-command*
                 :command-hash (command-fingerprint *mcp-tui-deterministic-command*)
                 :pass-p (mtsr-pass-p (upb-tui-scorecard bundle))
                 :missing-scenarios tui-missing))
         (pass (and (uet-pass-p epic3) (uet-pass-p epic4))))
    (make-unified-evidence-envelope
     :schema-version "uee-v1"
     :pass-p pass
     :epic3 epic3
     :epic4 epic4
     :detail (if pass
                 "Unified evidence envelope pass."
                 "Unified evidence envelope fail (missing scenarios or command drift).")
     :timestamp (get-universal-time))))

(defun unified-evidence-envelope->json (env)
  (declare (type unified-evidence-envelope env)
           (optimize (safety 3)))
  (labels ((track-json (tck)
             (with-output-to-string (s)
               (format s "{\"framework\":\"~A\",\"deterministic_command\":\"~A\",\"command_hash\":~D,\"pass\":~A,\"missing_scenarios\":["
                       (uet-framework tck)
                       (uet-deterministic-command tck)
                       (uet-command-hash tck)
                       (if (uet-pass-p tck) "true" "false"))
               (loop for sid in (uet-missing-scenarios tck)
                     for i from 0 do
                       (when (> i 0) (write-char #\, s))
                       (format s "\"~A\"" sid))
               (write-string "]}" s))))
    (with-output-to-string (s)
      (format s "{\"schema_version\":\"~A\",\"pass\":~A,\"epic3\":~A,\"epic4\":~A,\"detail\":\"~A\",\"timestamp\":~D}"
              (uee-schema-version env)
              (if (uee-pass-p env) "true" "false")
              (track-json (uee-epic3 env))
              (track-json (uee-epic4 env))
              (uee-detail env)
              (uee-timestamp env)))))
