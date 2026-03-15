;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; health-monitor-tests.lisp — Tests for adapter health monitor
;;;

(in-package #:orrery/harness-tests)

(define-test health-monitor)

;;; ─── Helpers ───

(defun make-hs (status ts &key (latency 10) (endpoint "/health"))
  (make-health-sample :endpoint endpoint :status status
                      :latency-ms latency :timestamp ts))

;;; ─── Backoff ───

(define-test (health-monitor backoff-initial)
  (let ((bs (make-backoff-state)))
    (multiple-value-bind (delay next) (compute-backoff bs)
      (is = 1000 delay)
      (is = 2000 (bs-current-ms next))
      (is = 1 (bs-attempt next)))))

(define-test (health-monitor backoff-escalation)
  (let ((bs (make-backoff-state :current-ms 2000 :attempt 1)))
    (multiple-value-bind (delay next) (compute-backoff bs)
      (is = 2000 delay)
      (is = 4000 (bs-current-ms next)))))

(define-test (health-monitor backoff-max-cap)
  (let ((bs (make-backoff-state :current-ms 50000 :max-ms 60000)))
    (multiple-value-bind (delay next) (compute-backoff bs)
      (is = 50000 delay)
      (is = 60000 (bs-current-ms next)))))

(define-test (health-monitor backoff-reset)
  (let* ((bs (make-backoff-state :current-ms 8000 :attempt 3))
         (reset (reset-backoff bs)))
    (is = 1000 (bs-current-ms reset))
    (is = 0 (bs-attempt reset))))

;;; ─── Probe ───

(define-test (health-monitor probe-fixture)
  (let ((sample (probe-health "http://fixture/health" 1000)))
    (is eq :up (hs-status sample))
    (is = 1000 (hs-timestamp sample))))

(define-test (health-monitor probe-non-fixture)
  (let ((sample (probe-health "http://unknown/health" 2000)))
    ;; Non-fixture endpoints return :down in stub mode
    (true (member (hs-status sample) '(:down :degraded)))))

;;; ─── Window Classification ───

(define-test (health-monitor windows-empty)
  (is = 0 (length (classify-windows '()))))

(define-test (health-monitor windows-single)
  (let ((windows (classify-windows (list (make-hs :up 1000)))))
    (is = 1 (length windows))
    (is eq :up (hw-status (first windows)))))

(define-test (health-monitor windows-transition)
  (let* ((samples (list (make-hs :up 1000)
                        (make-hs :up 2000)
                        (make-hs :down 3000)
                        (make-hs :down 4000)
                        (make-hs :up 5000)))
         (windows (classify-windows samples)))
    (is = 3 (length windows))
    (is eq :up (hw-status (first windows)))
    (is eq :down (hw-status (second windows)))
    (is eq :up (hw-status (third windows)))))

(define-test (health-monitor windows-all-same)
  (let ((windows (classify-windows (list (make-hs :up 1000)
                                         (make-hs :up 2000)
                                         (make-hs :up 3000)))))
    (is = 1 (length windows))
    (is = 3 (hw-sample-count (first windows)))))

;;; ─── Summary ───

(define-test (health-monitor summary-empty)
  (let ((s (build-health-summary '())))
    (is = 0 (hsum-total-probes s))
    (is = 0.0 (hsum-uptime-ratio s))))

(define-test (health-monitor summary-all-up)
  (let* ((samples (list (make-hs :up 1000 :latency 10)
                        (make-hs :up 2000 :latency 20)
                        (make-hs :up 3000 :latency 30)))
         (s (build-health-summary samples)))
    (is = 3 (hsum-total-probes s))
    (is = 3 (hsum-up-count s))
    (is = 0 (hsum-down-count s))
    (is = 1.0 (hsum-uptime-ratio s))
    (true (> (hsum-p50-latency-ms s) 0))
    (is = 1000 (hsum-first-probe-time s))
    (is = 3000 (hsum-last-probe-time s))))

(define-test (health-monitor summary-mixed)
  (let* ((samples (list (make-hs :up 1000)
                        (make-hs :down 2000)
                        (make-hs :up 3000)
                        (make-hs :down 4000)))
         (s (build-health-summary samples)))
    (is = 4 (hsum-total-probes s))
    (is = 2 (hsum-up-count s))
    (is = 2 (hsum-down-count s))
    (is = 0.5 (hsum-uptime-ratio s))))

(define-test (health-monitor summary-degraded-counts-as-up)
  (let* ((samples (list (make-hs :degraded 1000)
                        (make-hs :degraded 2000)))
         (s (build-health-summary samples)))
    (is = 1.0 (hsum-uptime-ratio s))
    (is = 2 (hsum-degraded-count s))))

;;; ─── JSON ───

(define-test (health-monitor json-output)
  (let* ((samples (list (make-hs :up 1000) (make-hs :down 2000)))
         (s (build-health-summary samples))
         (json (health-summary-to-json s)))
    (true (search "total_probes" json))
    (true (search "uptime_ratio" json))
    (true (search "window_count" json))))

;;; ─── Integration ───

(define-test (health-monitor full-cycle)
  (let* ((bs (make-backoff-state))
         ;; Probe fixture (success → reset)
         (sample1 (probe-health "http://fixture/health" 1000))
         (bs2 (if (eq :up (hs-status sample1))
                  (reset-backoff bs)
                  (nth-value 1 (compute-backoff bs))))
         ;; Probe unknown (failure → backoff)
         (sample2 (probe-health "http://unknown/health" 2000)))
    (declare (ignore bs2))
    (let ((summary (build-health-summary (list sample1 sample2))))
      (true (health-summary-p summary))
      (is = 2 (hsum-total-probes summary))
      (true (> (length (health-summary-to-json summary)) 50)))))
