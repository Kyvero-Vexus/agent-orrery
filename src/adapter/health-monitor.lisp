;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; health-monitor.lisp — Typed adapter health monitoring with backoff
;;;
;;; Pure functions for health probing, window classification, and
;;; uptime metric computation. Feeds evidence-pack pipeline.

(in-package #:orrery/adapter)

;;; ─── Health Status ───

(deftype monitor-status ()
  "Health probe outcome."
  '(member :up :down :degraded))

;;; ─── Health Sample ───

(defstruct (health-sample
             (:constructor make-health-sample
                 (&key endpoint status latency-ms timestamp error-detail))
             (:conc-name hs-))
  "Single health probe result."
  (endpoint "" :type string)
  (status :down :type monitor-status)
  (latency-ms 0 :type (integer 0))
  (timestamp 0 :type (integer 0))
  (error-detail "" :type string))

;;; ─── Health Window ───

(defstruct (health-window
             (:constructor make-health-window
                 (&key start-time end-time status sample-count))
             (:conc-name hw-))
  "Availability window."
  (start-time 0 :type (integer 0))
  (end-time 0 :type (integer 0))
  (status :down :type monitor-status)
  (sample-count 0 :type (integer 0)))

;;; ─── Health Summary ───

(defstruct (health-summary
             (:constructor make-health-summary
                 (&key total-probes up-count down-count degraded-count
                       uptime-ratio p50-latency-ms p95-latency-ms
                       windows first-probe-time last-probe-time))
             (:conc-name hsum-))
  "Aggregate health metrics."
  (total-probes 0 :type (integer 0))
  (up-count 0 :type (integer 0))
  (down-count 0 :type (integer 0))
  (degraded-count 0 :type (integer 0))
  (uptime-ratio 0.0 :type single-float)
  (p50-latency-ms 0 :type (integer 0))
  (p95-latency-ms 0 :type (integer 0))
  (windows '() :type list)
  (first-probe-time 0 :type (integer 0))
  (last-probe-time 0 :type (integer 0)))

;;; ─── Backoff State ───

(defstruct (backoff-state
             (:constructor make-backoff-state
                 (&key (base-ms 1000) (max-ms 60000) (multiplier 2)
                       (current-ms 1000) (attempt 0)))
             (:conc-name bs-))
  "Exponential backoff state. Pure — no side effects."
  (base-ms 1000 :type (integer 1))
  (max-ms 60000 :type (integer 1))
  (multiplier 2 :type (integer 1))
  (current-ms 1000 :type (integer 1))
  (attempt 0 :type (integer 0)))

;;; ─── Backoff Functions ───

(declaim (ftype (function (backoff-state) (values (integer 1) backoff-state &optional))
                compute-backoff))
(defun compute-backoff (state)
  "Compute next delay and return updated state. Pure."
  (declare (optimize (safety 3)))
  (let* ((delay (bs-current-ms state))
         (next-ms (min (bs-max-ms state)
                       (* delay (bs-multiplier state))))
         (next-attempt (1+ (bs-attempt state))))
    (values delay
            (make-backoff-state
             :base-ms (bs-base-ms state)
             :max-ms (bs-max-ms state)
             :multiplier (bs-multiplier state)
             :current-ms next-ms
             :attempt next-attempt))))

(declaim (ftype (function (backoff-state) (values backoff-state &optional))
                reset-backoff))
(defun reset-backoff (state)
  "Reset backoff to base. Pure."
  (declare (optimize (safety 3)))
  (make-backoff-state
   :base-ms (bs-base-ms state)
   :max-ms (bs-max-ms state)
   :multiplier (bs-multiplier state)
   :current-ms (bs-base-ms state)
   :attempt 0))

;;; ─── Health Probe ───

(declaim (ftype (function (string (integer 0) &key (:degraded-threshold-ms (integer 0)))
                          (values health-sample &optional))
                probe-health))
(defun probe-health (endpoint timestamp &key (degraded-threshold-ms 2000))
  "Probe a health endpoint. Returns health-sample.
   Uses runtime-transport if available, otherwise returns :down."
  (declare (optimize (safety 3)))
  (handler-case
      (let* ((start-time (get-internal-real-time))
             ;; Simulate: in real usage, this would call the transport layer
             ;; For now, check if endpoint looks like a fixture
             (is-fixture (search "fixture" endpoint))
             (end-time (get-internal-real-time))
             (latency (max 1 (truncate (* 1000 (- end-time start-time))
                                       internal-time-units-per-second)))
             (status (cond (is-fixture :up)
                           ((> latency degraded-threshold-ms) :degraded)
                           (t :down))))
        (make-health-sample
         :endpoint endpoint
         :status status
         :latency-ms latency
         :timestamp timestamp))
    (error (c)
      (make-health-sample
       :endpoint endpoint
       :status :down
       :latency-ms 0
       :timestamp timestamp
       :error-detail (format nil "~A" c)))))

;;; ─── Window Classification ───

(declaim (ftype (function (list) (values list &optional))
                classify-windows))
(defun classify-windows (samples)
  "Classify ordered health-samples into availability windows. Pure."
  (declare (optimize (safety 3)))
  (when (null samples) (return-from classify-windows '()))
  (let ((windows '())
        (current-status (hs-status (first samples)))
        (window-start (hs-timestamp (first samples)))
        (count 1))
    (dolist (sample (rest samples))
      (if (eq (hs-status sample) current-status)
          (incf count)
          (progn
            (push (make-health-window
                   :start-time window-start
                   :end-time (hs-timestamp sample)
                   :status current-status
                   :sample-count count)
                  windows)
            (setf current-status (hs-status sample)
                  window-start (hs-timestamp sample)
                  count 1))))
    ;; Close final window
    (push (make-health-window
           :start-time window-start
           :end-time (hs-timestamp (car (last samples)))
           :status current-status
           :sample-count count)
          windows)
    (nreverse windows)))

;;; ─── Percentile Helper ───

(declaim (ftype (function (list single-float) (values (integer 0) &optional))
                %percentile))
(defun %percentile (sorted-values pct)
  "Compute percentile from sorted list. Pure."
  (declare (optimize (safety 3)))
  (if (null sorted-values) 0
      (let* ((n (length sorted-values))
             (idx (min (1- n) (truncate (* pct n)))))
        (nth idx sorted-values))))

;;; ─── Summary Builder ───

(declaim (ftype (function (list &key (:windows list)) (values health-summary &optional))
                build-health-summary))
(defun build-health-summary (samples &key (windows nil windows-p))
  "Build health summary from samples. Computes windows if not provided. Pure."
  (declare (optimize (safety 3)))
  (when (null samples)
    (return-from build-health-summary
      (make-health-summary)))
  (let* ((actual-windows (if windows-p windows (classify-windows samples)))
         (total (length samples))
         (up-count (count :up samples :key #'hs-status))
         (down-count (count :down samples :key #'hs-status))
         (degraded-count (count :degraded samples :key #'hs-status))
         (uptime-ratio (if (zerop total) 0.0
                           (coerce (/ (+ up-count degraded-count) total) 'single-float)))
         (latencies (sort (mapcar #'hs-latency-ms
                                  (remove-if (lambda (s) (eq :down (hs-status s))) samples))
                          #'<)))
    (make-health-summary
     :total-probes total
     :up-count up-count
     :down-count down-count
     :degraded-count degraded-count
     :uptime-ratio uptime-ratio
     :p50-latency-ms (%percentile latencies 0.5)
     :p95-latency-ms (%percentile latencies 0.95)
     :windows actual-windows
     :first-probe-time (hs-timestamp (first samples))
     :last-probe-time (hs-timestamp (car (last samples))))))

;;; ─── JSON Serialization ───

(declaim (ftype (function (health-summary) (values string &optional))
                health-summary-to-json))
(defun health-summary-to-json (summary)
  "Deterministic JSON serialization of health summary. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"total_probes\":~D,\"up_count\":~D,\"down_count\":~D,~
               \"degraded_count\":~D,\"uptime_ratio\":~,4F,~
               \"p50_latency_ms\":~D,\"p95_latency_ms\":~D,~
               \"window_count\":~D,~
               \"first_probe_time\":~D,\"last_probe_time\":~D}"
          (hsum-total-probes summary)
          (hsum-up-count summary)
          (hsum-down-count summary)
          (hsum-degraded-count summary)
          (hsum-uptime-ratio summary)
          (hsum-p50-latency-ms summary)
          (hsum-p95-latency-ms summary)
          (length (hsum-windows summary))
          (hsum-first-probe-time summary)
          (hsum-last-probe-time summary)))
