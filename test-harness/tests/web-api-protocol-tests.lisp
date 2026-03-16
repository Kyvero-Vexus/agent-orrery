;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; web-api-protocol-tests.lisp — Web API typed protocol wiring checks
;;; Bead: agent-orrery-zww

(in-package #:orrery/harness-tests)

(define-test web-api-protocol-suite

  (define-test dashboard-summary-json-shape-preserved
    (let* ((sessions (list (orrery/domain:make-session-record
                            :id "s1" :agent-name "a" :channel "c"
                            :status :active :model "m" :created-at 1 :updated-at 2
                            :message-count 1 :total-tokens 10 :estimated-cost-cents 1)))
           (cron (list (orrery/domain:make-cron-record
                        :name "c1" :kind :periodic :interval-s 60 :status :active
                        :last-run-at 1 :next-run-at 2 :run-count 1 :last-error nil :description "d")))
           (health (list (orrery/domain:make-health-record
                          :component "gateway" :status :ok :message "ok"
                          :checked-at 1 :latency-ms 10)))
           (alerts (list (orrery/domain:make-alert-record
                          :id "a1" :severity :warning :title "t" :message "m"
                          :source "s" :fired-at 1 :acknowledged-p nil :snoozed-until nil)))
           (json (orrery/web:dashboard-summary-json sessions cron health alerts)))
      (true (search "\"session_count\":1" json))
      (true (search "\"active_count\":1" json))))

  (define-test sessions-health-json-still-valid
    (let* ((sessions (list (orrery/domain:make-session-record
                            :id "s1" :agent-name "a" :channel "c"
                            :status :active :model "m" :created-at 1 :updated-at 2
                            :message-count 1 :total-tokens 10 :estimated-cost-cents 1)))
           (health (list (orrery/domain:make-health-record
                          :component "gateway" :status :ok :message "ok"
                          :checked-at 1 :latency-ms 10)))
           (sjson (orrery/web:sessions-list-json sessions))
           (hjson (orrery/web:health-json health)))
      (true (search "\"id\":\"s1\"" sjson))
      (true (search "\"component\":\"gateway\"" hjson))))

  (define-test audit-and-analytics-json-still-valid
    (let* ((entry (orrery/domain:make-audit-trail-entry
                   :seq 1 :timestamp 1 :category "session-lifecycle" :severity "info"
                   :actor "sys" :summary "ok" :detail "d" :hash "abcdef"))
           (summary (orrery/domain:make-analytics-summary
                     :total-sessions 1 :avg-duration-s 60 :median-tokens 20
                     :avg-tokens-per-msg 10 :total-cost-cents 3))
           (bucket (orrery/domain:make-duration-bucket-record :label "<1min" :count 1))
           (eff (orrery/domain:make-efficiency-record
                 :session-id "s1" :tokens-per-message 10 :tokens-per-minute 12 :cost-per-1k 20))
           (ajson (orrery/web:audit-trail-json (list entry)))
           (xjson (orrery/web:analytics-json summary (list bucket) (list eff))))
      (true (search "\"category\":\"session-lifecycle\"" ajson))
      (true (search "\"total_sessions\":1" xjson))))

  (define-test contract-helper-detects-missing-field
    (handler-case
        (progn
          (orrery/web::%assert-web-ui-contract :status
                                               (list (cons :session_count 1))
                                               '(:session_count :active_count))
          (fail "Expected contract violation error"))
      (error ()
        (true t)))))
