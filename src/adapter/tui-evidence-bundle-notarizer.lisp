;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-evidence-bundle-notarizer.lisp — typed T1-T6 evidence bundle notarizer
;;; Bead: agent-orrery-xmsd

(in-package #:orrery/adapter)

;;; ── Notarization record ──────────────────────────────────────────────────────

(defstruct (tui-notarization-record (:conc-name tnr-))
  "Immutable notarization record for one T1-T6 scenario's evidence."
  (scenario-id       ""    :type string)
  (command           ""    :type string)
  (command-hash      0     :type integer)
  (transcript-digest ""    :type string)
  (artifact-digest   ""    :type string)
  (notarized-p       nil   :type boolean)
  (notarization-id   ""    :type string)
  (reject-codes      nil   :type list)
  (detail            ""    :type string))

;;; ── Bundle notarization ──────────────────────────────────────────────────────

(defstruct (tui-bundle-notarization (:conc-name tbn-))
  "Aggregate immutable notarization for all T1-T6 evidence."
  (bundle-id         ""    :type string)
  (command           ""    :type string)
  (command-hash      0     :type integer)
  (records           nil   :type list)
  (notarized-count   0     :type (integer 0))
  (rejected-count    0     :type (integer 0))
  (pass-p            nil   :type boolean)
  (timestamp         0     :type integer))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string string string string string)
                  (values tui-notarization-record &optional))
        build-tui-notarization-record)
 (ftype (function (string string) (values tui-bundle-notarization &optional))
        notarize-tui-evidence-bundle)
 (ftype (function (tui-bundle-notarization) (values string &optional))
        tui-bundle-notarization->json))

;;; ── Notarization ID ──────────────────────────────────────────────────────────

(defun %make-notarization-id (scenario-id command-hash transcript-digest artifact-digest)
  "Compute a deterministic notarization ID from evidence components."
  (declare (type string scenario-id transcript-digest artifact-digest)
           (type integer command-hash))
  (format nil "~A-~X-~X"
          scenario-id
          (logxor command-hash (sxhash transcript-digest))
          (sxhash artifact-digest)))

;;; ── Record builder ───────────────────────────────────────────────────────────

(defun build-tui-notarization-record (scenario-id command transcript-digest artifact-digest artifact-root)
  "Build an immutable notarization record for one T1-T6 scenario."
  (declare (type string scenario-id command transcript-digest artifact-digest artifact-root)
           (optimize (safety 3)))
  (let* ((cmd-hash    (command-fingerprint command))
         (canon-hash  (command-fingerprint *mcp-tui-deterministic-command*))
         (cmd-ok      (= cmd-hash canon-hash))
         (txd-ok      (plusp (length transcript-digest)))
         (artd-ok     (plusp (length artifact-digest)))
         (all-ok      (and cmd-ok txd-ok artd-ok))
         (reject-codes (append
                        (unless cmd-ok  (list (format nil "E3_NOTAR_CMD_DRIFT_~A" scenario-id)))
                        (unless txd-ok  (list (format nil "E3_NOTAR_TX_MISSING_~A" scenario-id)))
                        (unless artd-ok (list (format nil "E3_NOTAR_ART_MISSING_~A" scenario-id)))))
         (notar-id    (if all-ok
                          (%make-notarization-id scenario-id cmd-hash transcript-digest artifact-digest)
                          "")))
    (declare (ignore artifact-root))
    (make-tui-notarization-record
     :scenario-id       scenario-id
     :command           command
     :command-hash      cmd-hash
     :transcript-digest transcript-digest
     :artifact-digest   artifact-digest
     :notarized-p       all-ok
     :notarization-id   notar-id
     :reject-codes      reject-codes
     :detail            (if all-ok
                            (format nil "~A: notarized id=~A" scenario-id notar-id)
                            (format nil "~A: rejected ~{~A~^,~}" scenario-id reject-codes)))))

(defun notarize-tui-evidence-bundle (artifact-root command)
  "Notarize T1-T6 evidence from ARTIFACT-ROOT using COMMAND."
  (declare (type string artifact-root command)
           (optimize (safety 3)))
  (let* ((records
           (mapcar (lambda (sid)
                     (let* ((tx-path (format nil "~A~A-transcript.txt" artifact-root sid))
                            (art-path (format nil "~A~A.cast" artifact-root sid))
                            (tx-digest (if (probe-file tx-path)
                                           (%hash-text-file tx-path)
                                           ""))
                            (art-digest (if (probe-file art-path)
                                            (%hash-text-file art-path)
                                            "")))
                       (build-tui-notarization-record
                        sid command tx-digest art-digest artifact-root)))
                   *mcp-tui-required-scenarios*))
         (notarized (count-if #'tnr-notarized-p records))
         (rejected  (- (length records) notarized))
         (pass-p    (zerop rejected)))
    (make-tui-bundle-notarization
     :bundle-id       (format nil "tbn-~D" (get-universal-time))
     :command         command
     :command-hash    (command-fingerprint command)
     :records         records
     :notarized-count notarized
     :rejected-count  rejected
     :pass-p          pass-p
     :timestamp       (get-universal-time))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %tnr->json (r)
  (declare (type tui-notarization-record r))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"notarized\":~A,\"command_hash\":~D,\"notarization_id\":\"~A\",\"reject_codes\":["
            (tnr-scenario-id r)
            (if (tnr-notarized-p r) "true" "false")
            (tnr-command-hash r)
            (tnr-notarization-id r))
    (loop for c in (tnr-reject-codes r)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" c)))
    (format out "]}")))

(defun tui-bundle-notarization->json (bundle)
  (declare (type tui-bundle-notarization bundle))
  (with-output-to-string (out)
    (format out "{\"bundle_id\":\"~A\",\"command_hash\":~D,\"pass\":~A,\"notarized_count\":~D,\"rejected_count\":~D,\"timestamp\":~D,\"records\":["
            (tbn-bundle-id bundle)
            (tbn-command-hash bundle)
            (if (tbn-pass-p bundle) "true" "false")
            (tbn-notarized-count bundle)
            (tbn-rejected-count bundle)
            (tbn-timestamp bundle))
    (loop for r in (tbn-records bundle)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%tnr->json r) out)))
    (write-string "]}" out)))
