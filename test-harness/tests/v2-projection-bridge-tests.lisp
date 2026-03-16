;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; v2-projection-bridge-tests.lisp — Tests for audit/session analytics projection bridge
;;; Bead: agent-orrery-4zp

(in-package #:orrery/harness-tests)

(define-test v2-projection-bridge-suite

  (define-test audit-entry-projection
    (let* ((trail (orrery/coalton/core:cl-empty-trail))
           (entry (orrery/coalton/core:cl-make-single-entry
                   (lambda (s) (format nil "h-~A" s))
                   trail
                   1000 (orrery/coalton/core:cl-audit-session-lifecycle)
                   (orrery/coalton/core:cl-audit-info)
                   "system" "Session started" "details"))
           (proj (orrery/adapter:coalton-audit-entry->projection entry)))
      (is = 1000 (orrery/adapter:aep-timestamp proj))
      (is string= "system" (orrery/adapter:aep-actor proj))
      (true (search "session" (string-downcase (orrery/adapter:aep-category proj))))))

  (define-test audit-entry-json
    (let ((proj (orrery/adapter:make-audit-entry-projection
                 :seq 1 :timestamp 1000 :category "session" :severity "info"
                 :actor "system" :summary "ok" :detail "" :hash "h")))
      (let ((json (orrery/adapter:audit-entry-projection->json proj)))
        (true (search "\"seq\":1" json))
        (true (search "\"category\":\"session\"" json)))))

  (define-test analytics-projection
    (let* ((metrics (list
                     (orrery/coalton/core:cl-make-session-metric "s1" 120 2000 20 100 "gpt-4")
                     (orrery/coalton/core:cl-make-session-metric "s2" 600 6000 60 300 "claude-3")))
           (summary (orrery/coalton/core:cl-analyze-sessions metrics))
           (proj (orrery/adapter:coalton-analytics->projection summary)))
      (is = 2 (orrery/adapter:sap-total-sessions proj))
      (is = 400 (orrery/adapter:sap-total-cost-cents proj))
      (is = 5 (length (orrery/adapter:sap-duration-buckets proj)))
      (is = 2 (length (orrery/adapter:sap-efficiency-summaries proj)))))

  (define-test analytics-json
    (let* ((proj (orrery/adapter:make-session-analytics-projection
                  :total-sessions 2
                  :avg-duration-seconds 360
                  :avg-tokens-per-msg 100
                  :median-tokens 4000
                  :total-cost-cents 400
                  :duration-buckets (list (orrery/adapter:make-duration-bucket-projection
                                           :label "1-5min" :count 1))
                  :efficiency-summaries nil))
           (json (orrery/adapter:session-analytics-projection->json proj)))
      (true (search "\"total\":2" json))
      (true (search "\"avg_duration_s\":360" json))
      (true (search "\"buckets\"" json))))

  (define-test pagination-first-page
    (let* ((items (loop for i from 1 to 100 collect i))
           (req (orrery/adapter:make-page-request :offset 0 :limit 10 :sort-key :timestamp :sort-order :desc))
           (res (orrery/adapter:paginate-items items req)))
      (is = 10 (length (orrery/adapter:pres-items res)))
      (is = 100 (orrery/adapter:pres-total res))
      (is = 0 (orrery/adapter:pres-offset res))
      (true (orrery/adapter:pres-has-more-p res))))

  (define-test pagination-last-page
    (let* ((items (loop for i from 1 to 23 collect i))
           (req (orrery/adapter:make-page-request :offset 20 :limit 10 :sort-key :timestamp :sort-order :desc))
           (res (orrery/adapter:paginate-items items req)))
      (is = 3 (length (orrery/adapter:pres-items res)))
      (is = 23 (orrery/adapter:pres-total res))
      (false (orrery/adapter:pres-has-more-p res))))

  (define-test pagination-offset-clamp
    (let* ((items (loop for i from 1 to 5 collect i))
           (req (orrery/adapter:make-page-request :offset 999 :limit 10 :sort-key :timestamp :sort-order :desc))
           (res (orrery/adapter:paginate-items items req)))
      (is = 0 (length (orrery/adapter:pres-items res)))
      (is = 5 (orrery/adapter:pres-offset res))))

  (define-test projection-deterministic-order
    (let* ((items (list 1 2 3 4 5))
           (req (orrery/adapter:make-page-request :offset 1 :limit 3 :sort-key :timestamp :sort-order :desc))
           (res (orrery/adapter:paginate-items items req)))
      (is equal '(2 3 4) (orrery/adapter:pres-items res)))))
