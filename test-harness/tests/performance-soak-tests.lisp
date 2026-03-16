;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; performance-soak-tests.lisp — Tests for performance/soak suite
;;; Bead: agent-orrery-eb0.7.1

(in-package #:orrery/harness-tests)

(define-test performance-soak-suite

  (define-test light-profile-config
    (let ((cfg (orrery/adapter:make-soak-profile-config :light)))
      (is eq :light (orrery/adapter:sc-profile cfg))
      (is = 10 (orrery/adapter:sc-session-count cfg))
      (is = 100 (orrery/adapter:sc-event-count cfg))
      (is = 3 (orrery/adapter:sc-iterations cfg))))

  (define-test heavy-profile-config
    (let ((cfg (orrery/adapter:make-soak-profile-config :heavy)))
      (is eq :heavy (orrery/adapter:sc-profile cfg))
      (is = 500 (orrery/adapter:sc-session-count cfg))
      (is = 5000 (orrery/adapter:sc-event-count cfg))))

  (define-test measure-operation-timing
    (let ((timing (orrery/adapter:measure-operation
                   "test-op" 3
                   (lambda ()
                     (loop for i from 1 to 100 collect i)))))
      (is string= "test-op" (orrery/adapter:st-operation timing))
      (is = 3 (orrery/adapter:st-iterations timing))
      (true (>= (orrery/adapter:st-total-ms timing) 0))
      (true (<= (orrery/adapter:st-min-ms timing) (orrery/adapter:st-max-ms timing)))
      (true (> (orrery/adapter:st-items-processed timing) 0))))

  (define-test light-soak-passes
    (let* ((cfg (orrery/adapter:make-soak-profile-config :light))
           (report (orrery/adapter:run-soak-suite cfg :timestamp 1000)))
      (true (orrery/adapter:srep-pass-p report))
      (is eq :light (orrery/adapter:srep-profile report))
      (is = 6 (length (orrery/adapter:srep-timings report)))
      (true (> (orrery/adapter:srep-total-ms report) 0))
      (true (> (orrery/adapter:srep-peak-memory-kb report) 0))))

  (define-test medium-soak-passes
    (let* ((cfg (orrery/adapter:make-soak-profile-config :medium))
           (report (orrery/adapter:run-soak-suite cfg :timestamp 2000)))
      (true (orrery/adapter:srep-pass-p report))
      (is = 6 (length (orrery/adapter:srep-timings report)))))

  (define-test soak-report-json-shape
    (let* ((cfg (orrery/adapter:make-soak-profile-config :light))
           (report (orrery/adapter:run-soak-suite cfg :timestamp 3000))
           (json (orrery/adapter:soak-report->json report)))
      (true (search "\"profile\":\"light\"" json))
      (true (search "\"pass\":true" json))
      (true (search "\"timings\"" json))
      (true (search "\"peak_memory_kb\"" json))))

  (define-test timing-json-shape
    (let ((timing (orrery/adapter:make-soak-timing
                   :operation "test" :iterations 1 :total-ms 5
                   :min-ms 5 :max-ms 5 :mean-ms 5
                   :items-processed 10 :throughput-per-sec 2000)))
      (let ((json (orrery/adapter:soak-timing->json timing)))
        (true (search "\"op\":\"test\"" json))
        (true (search "\"throughput\":2000" json))))))
