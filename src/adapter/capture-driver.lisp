;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capture-driver.lisp — Live runtime capture driver for normalized event snapshots
;;;
;;; Samples endpoints from fixture or live runtime, normalizes responses,
;;; and emits validated artifact envelopes for Epic 2 gate consumption.

(in-package #:orrery/adapter)

;;; ─── Capture Target ───

(deftype capture-profile ()
  "Runtime profile for capture."
  '(member :fixture :live :synthetic))

(defstruct (capture-target
             (:constructor make-capture-target
                 (&key base-url token profile timeout-ms))
             (:conc-name ct-))
  "Target runtime for capture operations."
  (base-url "" :type string)
  (token "" :type string)
  (profile :fixture :type capture-profile)
  (timeout-ms 5000 :type (integer 0)))

;;; ─── Endpoint Sample ───

(defstruct (endpoint-sample
             (:constructor make-endpoint-sample
                 (&key endpoint status-code body latency-ms
                       timestamp error-p))
             (:conc-name es-))
  "One sampled endpoint response."
  (endpoint "" :type string)
  (status-code 0 :type (integer 0 999))
  (body "" :type string)
  (latency-ms 0 :type (integer 0))
  (timestamp 0 :type (integer 0))
  (error-p nil :type boolean))

;;; ─── Capture Snapshot ───

(defstruct (capture-snapshot
             (:constructor make-capture-snapshot
                 (&key snapshot-id target samples timestamp duration-ms))
             (:conc-name cs-))
  "Complete snapshot from one capture pass."
  (snapshot-id "" :type string)
  (target (make-capture-target) :type capture-target)
  (samples '() :type list)
  (timestamp 0 :type (integer 0))
  (duration-ms 0 :type (integer 0)))

;;; ─── Capture Result ───

(defstruct (capture-result
             (:constructor make-capture-result
                 (&key snapshots artifacts diagnostics success-p))
             (:conc-name cres-))
  "Aggregate result of a capture operation."
  (snapshots '() :type list)
  (artifacts '() :type list)
  (diagnostics '() :type list)
  (success-p nil :type boolean))

;;; ─── Fixture Endpoint Data ───

(defparameter *fixture-endpoints*
  '(("/api/v1/sessions" . "{\"sessions\":[]}")
    ("/api/v1/cron" . "{\"jobs\":[]}")
    ("/api/v1/health" . "{\"status\":\"ok\"}")
    ("/api/v1/events" . "{\"events\":[]}")
    ("/api/v1/alerts" . "{\"alerts\":[]}")
    ("/api/v1/usage" . "{\"usage\":{}}"))
  "Standard fixture endpoint responses for testing.")

;;; ─── Endpoint Sampler ───

(declaim (ftype (function (capture-target string (integer 0)) endpoint-sample)
                sample-fixture-endpoint))
(defun sample-fixture-endpoint (target endpoint timestamp)
  "Sample an endpoint from fixture data. Pure — no I/O."
  (declare (optimize (safety 3))
           (ignore target))
  (let ((fixture (assoc endpoint *fixture-endpoints* :test #'string=)))
    (if fixture
        (make-endpoint-sample
         :endpoint endpoint
         :status-code 200
         :body (cdr fixture)
         :latency-ms 1
         :timestamp timestamp
         :error-p nil)
        (make-endpoint-sample
         :endpoint endpoint
         :status-code 404
         :body ""
         :latency-ms 0
         :timestamp timestamp
         :error-p t))))

(declaim (ftype (function (capture-target string (integer 0)) endpoint-sample)
                sample-endpoint))
(defun sample-endpoint (target endpoint timestamp)
  "Sample an endpoint. Dispatches to fixture or live sampler.
   Live sampling returns a synthetic timeout for now (needs ORRERY_OPENCLAW_BASE_URL)."
  (declare (optimize (safety 3)))
  (ecase (ct-profile target)
    (:fixture (sample-fixture-endpoint target endpoint timestamp))
    (:synthetic (sample-fixture-endpoint target endpoint timestamp))
    (:live
     ;; Live would do HTTP here — returns transport error until env wiring
     (make-endpoint-sample
      :endpoint endpoint
      :status-code 0
      :body ""
      :latency-ms (ct-timeout-ms target)
      :timestamp timestamp
      :error-p t))))

;;; ─── Response Normalizer ───

(declaim (ftype (function (endpoint-sample) probe-finding)
                normalize-sample-to-finding))
(defun normalize-sample-to-finding (sample)
  "Normalize an endpoint sample into a probe finding for the decision pipeline."
  (declare (optimize (safety 3)))
  (let* ((error-p (es-error-p sample))
         (status (es-status-code sample))
         (domain (cond
                   ((string= (es-endpoint sample) "/api/v1/health") :transport)
                   ((string= (es-endpoint sample) "/api/v1/sessions") :runtime)
                   ((string= (es-endpoint sample) "/api/v1/alerts") :auth)
                   (t :conformance)))
         (health (cond
                   (error-p :unhealthy)
                   ((and (>= status 200) (< status 300)) :healthy)
                   ((and (>= status 300) (< status 500)) :degraded)
                   (t :unhealthy))))
    (make-probe-finding
     :domain domain
     :status health
     :severity (status-to-severity health domain)
     :message (format nil "~A: HTTP ~D (~Dms)"
                      (es-endpoint sample) status (es-latency-ms sample))
     :evidence-ref (format nil "capture:~A:~D"
                           (es-endpoint sample) (es-timestamp sample)))))

;;; ─── Snapshot Assembler ───

(declaim (ftype (function (capture-target list (integer 0) string)
                          capture-snapshot)
                assemble-snapshot))
(defun assemble-snapshot (target endpoints timestamp snapshot-id)
  "Sample all endpoints and assemble into a capture snapshot."
  (declare (optimize (safety 3)))
  (let ((samples '())
        (start-ts timestamp))
    (dolist (ep endpoints)
      (push (sample-endpoint target ep timestamp) samples)
      (incf timestamp))  ; simulate sequential sampling
    (make-capture-snapshot
     :snapshot-id snapshot-id
     :target target
     :samples (nreverse samples)
     :timestamp start-ts
     :duration-ms (- timestamp start-ts))))

;;; ─── Snapshot → Artifact Envelope ───

(declaim (ftype (function (capture-snapshot) artifact-envelope)
                snapshot-to-artifact))
(defun snapshot-to-artifact (snapshot)
  "Wrap a capture snapshot in a validated artifact envelope."
  (declare (optimize (safety 3)))
  (let* ((body-size (reduce #'+ (cs-samples snapshot)
                            :key (lambda (s) (length (es-body s)))))
         (has-errors (some #'es-error-p (cs-samples snapshot)))
         (envelope (make-artifact-envelope
                    :artifact-id (cs-snapshot-id snapshot)
                    :kind :evidence-bundle
                    :version "1.0.0"
                    :created-at (cs-timestamp snapshot)
                    :source (ct-profile (cs-target snapshot))
                    :checksum (format nil "sha256:~A" (cs-snapshot-id snapshot))
                    :payload-size body-size)))
    ;; Validate envelope
    (let ((errors (validate-envelope envelope)))
      (make-artifact-envelope
       :artifact-id (ae-artifact-id envelope)
       :kind (ae-kind envelope)
       :version (ae-version envelope)
       :created-at (ae-created-at envelope)
       :source (ae-source envelope)
       :checksum (ae-checksum envelope)
       :payload-size (ae-payload-size envelope)
       :valid-p (and (null errors) (not has-errors))
       :errors errors))))

;;; ─── Snapshot → Replay Stream ───

(declaim (ftype (function (capture-snapshot) replay-stream)
                snapshot-to-replay-stream))
(defun snapshot-to-replay-stream (snapshot)
  "Convert a capture snapshot to a replay stream for decision pipeline input."
  (declare (optimize (safety 3)))
  (let ((events '())
        (seq 0))
    (dolist (sample (cs-samples snapshot))
      (incf seq)
      (push (make-replay-event
             :sequence-id seq
             :event-type (cond
                           ((search "sessions" (es-endpoint sample)) :session)
                           ((search "cron" (es-endpoint sample)) :cron)
                           ((search "health" (es-endpoint sample)) :health)
                           ((search "events" (es-endpoint sample)) :event)
                           ((search "alerts" (es-endpoint sample)) :alert)
                           ((search "usage" (es-endpoint sample)) :usage)
                           (t :probe))
             :payload (es-body sample)
             :timestamp (es-timestamp sample))
            events))
    (make-replay-stream
     :stream-id (cs-snapshot-id snapshot)
     :source (ct-profile (cs-target snapshot))
     :events (nreverse events)
     :seed (cs-timestamp snapshot)
     :metadata (format nil "Captured from ~A at ~D"
                       (ct-base-url (cs-target snapshot))
                       (cs-timestamp snapshot)))))

;;; ─── Full Capture Pipeline ───

(declaim (ftype (function (capture-target &key (:endpoints list)
                                              (:timestamp (integer 0))
                                              (:snapshot-id string))
                          capture-result)
                run-capture))
(defun run-capture (target &key
                             (endpoints (mapcar #'car *fixture-endpoints*))
                             (timestamp 0)
                             (snapshot-id "snap-001"))
  "Run full capture pipeline: sample → assemble → validate → emit.
   Returns capture-result with snapshots, artifacts, and diagnostics."
  (declare (optimize (safety 3)))
  (let* ((snapshot (assemble-snapshot target endpoints timestamp snapshot-id))
         (artifact (snapshot-to-artifact snapshot))
         (diagnostics '()))
    ;; Collect diagnostics
    (dolist (s (cs-samples snapshot))
      (when (es-error-p s)
        (push (format nil "ERROR: ~A returned status ~D"
                      (es-endpoint s) (es-status-code s))
              diagnostics)))
    (unless (ae-valid-p artifact)
      (push (format nil "WARN: artifact ~A failed validation (~D errors)"
                    (ae-artifact-id artifact) (length (ae-errors artifact)))
            diagnostics))
    (make-capture-result
     :snapshots (list snapshot)
     :artifacts (list artifact)
     :diagnostics (nreverse diagnostics)
     :success-p (and (ae-valid-p artifact)
                     (notany #'es-error-p (cs-samples snapshot))))))

;;; ─── Capture → Decision (Integration) ───

(declaim (ftype (function (capture-result &key (:thresholds severity-thresholds))
                          decision-record)
                capture-to-decision))
(defun capture-to-decision (result &key (thresholds (make-severity-thresholds)))
  "Feed capture results through the decision pipeline.
   Converts snapshots to findings and runs the verdict engine."
  (declare (optimize (safety 3)))
  (let ((findings '()))
    (dolist (snapshot (cres-snapshots result))
      (dolist (sample (cs-samples snapshot))
        (push (normalize-sample-to-finding sample) findings)))
    (run-decision-pipeline (nreverse findings) :thresholds thresholds)))
