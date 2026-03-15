;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; evidence-pack.lisp — Epic 2 gate evidence pack: parity report + replay manifests
;;;
;;; Produces the gate evidence bundle with fixture vs live parity report,
;;; replay manifests, and reproducible commands for eb0.2.5 closure.

(in-package #:orrery/adapter)

;;; ─── Parity Classification ───

(deftype parity-verdict ()
  "Outcome of fixture vs live comparison."
  '(member :identical :compatible :degraded :incompatible :live-unavailable))

;;; ─── Endpoint Parity Entry ───

(defstruct (parity-entry
             (:constructor make-parity-entry
                 (&key endpoint fixture-status live-status
                       fixture-body-hash live-body-hash
                       verdict detail))
             (:conc-name pe-))
  "One endpoint's fixture vs live comparison."
  (endpoint "" :type string)
  (fixture-status 0 :type (integer 0 999))
  (live-status 0 :type (integer 0 999))
  (fixture-body-hash "" :type string)
  (live-body-hash "" :type string)
  (verdict :live-unavailable :type parity-verdict)
  (detail "" :type string))

;;; ─── Parity Report ───

(defstruct (parity-report
             (:constructor make-parity-report
                 (&key report-id fixture-snapshot-id live-snapshot-id
                       entries overall-verdict endpoint-count
                       identical-count compatible-count
                       degraded-count incompatible-count
                       timestamp))
             (:conc-name pr-))
  "Aggregate fixture vs live parity report."
  (report-id "" :type string)
  (fixture-snapshot-id "" :type string)
  (live-snapshot-id "" :type string)
  (entries '() :type list)
  (overall-verdict :live-unavailable :type parity-verdict)
  (endpoint-count 0 :type (integer 0))
  (identical-count 0 :type (integer 0))
  (compatible-count 0 :type (integer 0))
  (degraded-count 0 :type (integer 0))
  (incompatible-count 0 :type (integer 0))
  (timestamp 0 :type (integer 0)))

;;; ─── Replay Manifest ───

(defstruct (replay-manifest-entry
             (:constructor make-replay-manifest-entry
                 (&key stream-id source event-count seed
                       artifact-id valid-p))
             (:conc-name rme-))
  "One entry in a replay manifest."
  (stream-id "" :type string)
  (source :fixture :type replay-source)
  (event-count 0 :type (integer 0))
  (seed 0 :type (integer 0))
  (artifact-id "" :type string)
  (valid-p nil :type boolean))

(defstruct (replay-manifest
             (:constructor make-replay-manifest
                 (&key manifest-id entries stream-count
                       valid-count invalid-count timestamp))
             (:conc-name rm-))
  "Complete manifest of replay streams for gate consumption."
  (manifest-id "" :type string)
  (entries '() :type list)
  (stream-count 0 :type (integer 0))
  (valid-count 0 :type (integer 0))
  (invalid-count 0 :type (integer 0))
  (timestamp 0 :type (integer 0)))

;;; ─── Evidence Pack ───

(defstruct (evidence-pack
             (:constructor make-evidence-pack
                 (&key pack-id parity-report replay-manifest
                       fixture-decision live-decision
                       fixture-artifact live-artifact
                       gate-ready-p blockers timestamp
                       repro-commands))
             (:conc-name ep-))
  "Complete Epic 2 gate evidence pack."
  (pack-id "" :type string)
  (parity-report (make-parity-report) :type parity-report)
  (replay-manifest (make-replay-manifest) :type replay-manifest)
  (fixture-decision nil :type (or null decision-record))
  (live-decision nil :type (or null decision-record))
  (fixture-artifact nil :type (or null artifact-envelope))
  (live-artifact nil :type (or null artifact-envelope))
  (gate-ready-p nil :type boolean)
  (blockers '() :type list)
  (timestamp 0 :type (integer 0))
  (repro-commands '() :type list))

;;; ─── Body Hash ───

(declaim (ftype (function (string) string) simple-body-hash))
(defun simple-body-hash (body)
  "Produce a simple deterministic hash of a response body.
   Uses length + first/last chars as a lightweight fingerprint."
  (declare (optimize (safety 3)))
  (let ((len (length body)))
    (if (= len 0)
        "empty"
        (format nil "len:~D:~A...~A"
                len
                (subseq body 0 (min 8 len))
                (subseq body (max 0 (- len 4)))))))

;;; ─── Compare Endpoint Samples ───

(declaim (ftype (function (endpoint-sample endpoint-sample) parity-entry)
                compare-endpoint-samples))
(defun compare-endpoint-samples (fixture-sample live-sample)
  "Compare a fixture and live endpoint sample. Pure."
  (declare (optimize (safety 3)))
  (let* ((f-status (es-status-code fixture-sample))
         (l-status (es-status-code live-sample))
         (f-hash (simple-body-hash (es-body fixture-sample)))
         (l-hash (simple-body-hash (es-body live-sample)))
         (live-error (es-error-p live-sample))
         (verdict (cond
                    (live-error :live-unavailable)
                    ((and (= f-status l-status)
                          (string= f-hash l-hash))
                     :identical)
                    ((= f-status l-status) :compatible)
                    ((and (>= l-status 200) (< l-status 300)) :compatible)
                    ((and (>= l-status 300) (< l-status 500)) :degraded)
                    (t :incompatible))))
    (make-parity-entry
     :endpoint (es-endpoint fixture-sample)
     :fixture-status f-status
     :live-status l-status
     :fixture-body-hash f-hash
     :live-body-hash l-hash
     :verdict verdict
     :detail (cond
               (live-error "Live endpoint unreachable")
               ((eq verdict :identical) "Exact match")
               ((eq verdict :compatible) "Status match, body differs")
               ((eq verdict :degraded)
                (format nil "Status mismatch: fixture=~D live=~D" f-status l-status))
               (t (format nil "Incompatible: fixture=~D live=~D" f-status l-status))))))

;;; ─── Build Parity Report ───

(declaim (ftype (function (capture-snapshot capture-snapshot string (integer 0))
                          parity-report)
                build-parity-report))
(defun build-parity-report (fixture-snapshot live-snapshot report-id timestamp)
  "Compare fixture and live snapshots endpoint-by-endpoint. Pure."
  (declare (optimize (safety 3)))
  (let ((entries '())
        (identical 0) (compatible 0) (degraded 0) (incompatible 0))
    ;; Match samples by endpoint
    (dolist (f-sample (cs-samples fixture-snapshot))
      (let ((l-sample (find (es-endpoint f-sample)
                            (cs-samples live-snapshot)
                            :key #'es-endpoint :test #'string=)))
        (if l-sample
            (let ((entry (compare-endpoint-samples f-sample l-sample)))
              (push entry entries)
              (ecase (pe-verdict entry)
                (:identical (incf identical))
                (:compatible (incf compatible))
                (:degraded (incf degraded))
                (:incompatible (incf incompatible))
                (:live-unavailable (incf incompatible))))
            ;; No live sample for this endpoint
            (push (make-parity-entry
                   :endpoint (es-endpoint f-sample)
                   :fixture-status (es-status-code f-sample)
                   :live-status 0
                   :verdict :live-unavailable
                   :detail "No live sample for endpoint")
                  entries))))
    (let* ((total (length entries))
           (overall (cond
                      ((> incompatible 0) :incompatible)
                      ((> degraded 0) :degraded)
                      ((= identical total) :identical)
                      ((> compatible 0) :compatible)
                      (t :live-unavailable))))
      (make-parity-report
       :report-id report-id
       :fixture-snapshot-id (cs-snapshot-id fixture-snapshot)
       :live-snapshot-id (cs-snapshot-id live-snapshot)
       :entries (nreverse entries)
       :overall-verdict overall
       :endpoint-count total
       :identical-count identical
       :compatible-count compatible
       :degraded-count degraded
       :incompatible-count incompatible
       :timestamp timestamp))))

;;; ─── Build Replay Manifest ───

(declaim (ftype (function (list list string (integer 0)) replay-manifest)
                build-replay-manifest))
(defun build-replay-manifest (streams artifacts manifest-id timestamp)
  "Build a replay manifest from streams and their artifact envelopes. Pure."
  (declare (optimize (safety 3)))
  (let ((entries '())
        (valid 0) (invalid 0))
    (loop for stream in streams
          for artifact in artifacts
          do (let ((valid-p (ae-valid-p artifact)))
               (push (make-replay-manifest-entry
                      :stream-id (rstr-stream-id stream)
                      :source (rstr-source stream)
                      :event-count (length (rstr-events stream))
                      :seed (rstr-seed stream)
                      :artifact-id (ae-artifact-id artifact)
                      :valid-p valid-p)
                     entries)
               (if valid-p (incf valid) (incf invalid))))
    (make-replay-manifest
     :manifest-id manifest-id
     :entries (nreverse entries)
     :stream-count (+ valid invalid)
     :valid-count valid
     :invalid-count invalid
     :timestamp timestamp)))

;;; ─── Repro Commands ───

(declaim (ftype (function (capture-target capture-target) list)
                generate-repro-commands))
(defun generate-repro-commands (fixture-target live-target)
  "Generate reproducible commands for re-running evidence capture. Pure."
  (declare (optimize (safety 3))
           (ignore fixture-target))
  (list
   (format nil "# Fixture capture:")
   (format nil "sbcl --eval '(asdf:load-system \"agent-orrery\")' \\")
   (format nil "     --eval '(orrery/adapter:run-capture ~
                  (orrery/adapter:make-capture-target :profile :fixture))'")
   (format nil "")
   (format nil "# Live capture (requires ORRERY_OPENCLAW_BASE_URL):")
   (format nil "export ORRERY_OPENCLAW_BASE_URL=~A" (ct-base-url live-target))
   (format nil "sbcl --eval '(asdf:load-system \"agent-orrery\")' \\")
   (format nil "     --eval '(orrery/adapter:run-capture ~
                  (orrery/adapter:make-capture-target :base-url \"~A\" ~
                   :profile :live :token \"$ORRERY_TOKEN\"))'~%"
           (ct-base-url live-target))
   (format nil "# Full test suite:")
   (format nil "sbcl --eval '(asdf:test-system \"agent-orrery/test-harness\")'")))

;;; ─── Build Evidence Pack ───

(declaim (ftype (function (capture-result capture-result
                           &key (:pack-id string)
                                (:timestamp (integer 0)))
                          evidence-pack)
                build-evidence-pack))
(defun build-evidence-pack (fixture-result live-result
                            &key (pack-id "ep-001") (timestamp 0))
  "Build the complete Epic 2 gate evidence pack from fixture and live
   capture results. Pure function."
  (declare (optimize (safety 3)))
  (let* ((f-snapshot (first (cres-snapshots fixture-result)))
         (l-snapshot (first (cres-snapshots live-result)))
         (f-artifact (first (cres-artifacts fixture-result)))
         (l-artifact (first (cres-artifacts live-result)))
         ;; Build parity report
         (parity (build-parity-report f-snapshot l-snapshot
                                       (format nil "~A-parity" pack-id) timestamp))
         ;; Build replay streams + manifest
         (f-stream (snapshot-to-replay-stream f-snapshot))
         (l-stream (snapshot-to-replay-stream l-snapshot))
         (manifest (build-replay-manifest
                    (list f-stream l-stream)
                    (list f-artifact l-artifact)
                    (format nil "~A-manifest" pack-id) timestamp))
         ;; Decision pipeline
         (f-decision (capture-to-decision fixture-result))
         (l-decision (capture-to-decision live-result))
         ;; Determine gate readiness
         (fixture-ok (and (cres-success-p fixture-result)
                          (eq (dec-verdict f-decision) :pass)))
         (live-ok (cres-success-p live-result))
         ;; Collect blockers
         (blockers '())
         (repro (generate-repro-commands
                 (cs-target f-snapshot) (cs-target l-snapshot))))
    ;; Check for blockers
    (unless fixture-ok
      (push "Fixture capture did not produce passing verdict" blockers))
    (unless live-ok
      (push "Live runtime capture failed — env wiring or runtime not available" blockers))
    (when (member (pr-overall-verdict parity) '(:incompatible :degraded))
      (push (format nil "Parity verdict: ~A" (pr-overall-verdict parity)) blockers))
    (make-evidence-pack
     :pack-id pack-id
     :parity-report parity
     :replay-manifest manifest
     :fixture-decision f-decision
     :live-decision l-decision
     :fixture-artifact f-artifact
     :live-artifact l-artifact
     :gate-ready-p (and fixture-ok live-ok (null blockers))
     :blockers (nreverse blockers)
     :timestamp timestamp
     :repro-commands repro)))

;;; ─── JSON Serialization ───

(declaim (ftype (function (parity-entry) string) parity-entry-to-json))
(defun parity-entry-to-json (entry)
  "Serialize a parity entry to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"endpoint\":~S,\"fixture_status\":~D,\"live_status\":~D,~
               \"verdict\":~S,\"detail\":~S}"
          (pe-endpoint entry) (pe-fixture-status entry) (pe-live-status entry)
          (symbol-name (pe-verdict entry)) (pe-detail entry)))

(declaim (ftype (function (parity-report) string) parity-report-to-json))
(defun parity-report-to-json (report)
  "Serialize a parity report to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"report_id\":~S,\"fixture_snapshot\":~S,\"live_snapshot\":~S,~
               \"overall_verdict\":~S,\"endpoint_count\":~D,~
               \"identical\":~D,\"compatible\":~D,\"degraded\":~D,~
               \"incompatible\":~D,\"entries\":[~{~A~^,~}]}"
          (pr-report-id report)
          (pr-fixture-snapshot-id report)
          (pr-live-snapshot-id report)
          (symbol-name (pr-overall-verdict report))
          (pr-endpoint-count report)
          (pr-identical-count report)
          (pr-compatible-count report)
          (pr-degraded-count report)
          (pr-incompatible-count report)
          (mapcar #'parity-entry-to-json (pr-entries report))))

(declaim (ftype (function (replay-manifest) string) replay-manifest-to-json))
(defun replay-manifest-to-json (manifest)
  "Serialize a replay manifest to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"manifest_id\":~S,\"stream_count\":~D,~
               \"valid\":~D,\"invalid\":~D,\"entries\":[~{~A~^,~}]}"
          (rm-manifest-id manifest)
          (rm-stream-count manifest)
          (rm-valid-count manifest)
          (rm-invalid-count manifest)
          (mapcar (lambda (e)
                    (format nil "{\"stream_id\":~S,\"source\":~S,~
                                 \"event_count\":~D,\"valid\":~A}"
                            (rme-stream-id e)
                            (symbol-name (rme-source e))
                            (rme-event-count e)
                            (if (rme-valid-p e) "true" "false")))
                  (rm-entries manifest))))

(declaim (ftype (function (evidence-pack) string) evidence-pack-to-json))
(defun evidence-pack-to-json (pack)
  "Serialize evidence pack summary to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"pack_id\":~S,\"gate_ready\":~A,~
               \"fixture_verdict\":~S,\"live_verdict\":~S,~
               \"parity_verdict\":~S,~
               \"manifest_streams\":~D,\"manifest_valid\":~D,~
               \"blockers\":[~{~S~^,~}],~
               \"repro_commands\":~D}"
          (ep-pack-id pack)
          (if (ep-gate-ready-p pack) "true" "false")
          (if (ep-fixture-decision pack)
              (symbol-name (dec-verdict (ep-fixture-decision pack)))
              "null")
          (if (ep-live-decision pack)
              (symbol-name (dec-verdict (ep-live-decision pack)))
              "null")
          (symbol-name (pr-overall-verdict (ep-parity-report pack)))
          (rm-stream-count (ep-replay-manifest pack))
          (rm-valid-count (ep-replay-manifest pack))
          (ep-blockers pack)
          (length (ep-repro-commands pack))))
