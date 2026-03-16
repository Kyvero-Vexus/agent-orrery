;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-provider-tests.lisp — Tests for orrery/provider TUI data provider
;;;
;;; Bead: agent-orrery-87i

(in-package #:orrery/harness-tests)

(define-test tui-provider-suite)

;;; ============================================================
;;; Test fixtures
;;; ============================================================

(defvar *test-now* 1000000
  "Fixed time point for deterministic age calculations.")

(defun make-test-store ()
  "Build a sync-store with known test data."
  (orrery/store:make-sync-store
   :sessions (list
              (orrery/domain:make-session-record
               :id "s1" :agent-name "gensym" :channel "webchat"
               :status :active :model "claude-opus-4-20250514"
               :created-at 999000 :updated-at 999900
               :message-count 10 :total-tokens 5000
               :estimated-cost-cents 50)
              (orrery/domain:make-session-record
               :id "s2" :agent-name "chryso" :channel "telegram"
               :status :closed :model "claude-sonnet-4-20250514"
               :created-at 998000 :updated-at 999500
               :message-count 5 :total-tokens 1500
               :estimated-cost-cents 15)
              (orrery/domain:make-session-record
               :id "s3" :agent-name "gensym" :channel "webchat"
               :status :active :model "claude-opus-4-20250514"
               :created-at 997000 :updated-at 999800
               :message-count 20 :total-tokens 12000
               :estimated-cost-cents 120))
   :cron-jobs (list
               (orrery/domain:make-cron-record
                :name "health-check" :kind :periodic :interval-s 300
                :status :active :last-run-at 999700 :next-run-at 1000200
                :run-count 100 :last-error nil :description "Health poller")
               (orrery/domain:make-cron-record
                :name "sync-data" :kind :periodic :interval-s 3600
                :status :active :last-run-at 996000 :next-run-at 999600
                :run-count 20 :last-error "timeout" :description "Data sync")
               (orrery/domain:make-cron-record
                :name "cleanup" :kind :periodic :interval-s 86400
                :status :paused :last-run-at 950000 :next-run-at 1036400
                :run-count 5 :last-error nil :description "Daily cleanup"))
   :health (list
            (orrery/domain:make-health-record
             :component "gateway" :status :ok :message "Healthy"
             :checked-at 999900 :latency-ms 12)
            (orrery/domain:make-health-record
             :component "sbcl" :status :ok :message "Running"
             :checked-at 999900 :latency-ms 3)
            (orrery/domain:make-health-record
             :component "adapter" :status :degraded :message "Slow"
             :checked-at 999900 :latency-ms 250))
   :usage (list
           (orrery/domain:make-usage-record
            :model "claude-opus-4-20250514" :period :hourly :timestamp 999000
            :prompt-tokens 3000 :completion-tokens 2000 :total-tokens 5000
            :estimated-cost-cents 50)
           (orrery/domain:make-usage-record
            :model "claude-sonnet-4-20250514" :period :hourly :timestamp 999000
            :prompt-tokens 1000 :completion-tokens 500 :total-tokens 1500
            :estimated-cost-cents 15))
   :events (list
            (orrery/domain:make-event-record
             :id "e1" :kind :info :source "gateway" :message "Session started"
             :timestamp 999000)
            (orrery/domain:make-event-record
             :id "e2" :kind :warning :source "cron" :message "Slow response"
             :timestamp 999500)
            (orrery/domain:make-event-record
             :id "e3" :kind :error :source "adapter" :message "Connection failed"
             :timestamp 999800))
   :alerts (list
            (orrery/domain:make-alert-record
             :id "a1" :severity :critical :title "Down" :message "Adapter down"
             :source "monitor" :fired-at 999700
             :acknowledged-p nil :snoozed-until nil)
            (orrery/domain:make-alert-record
             :id "a2" :severity :warning :title "Slow" :message "High latency"
             :source "monitor" :fired-at 999500
             :acknowledged-p t :snoozed-until nil)
            (orrery/domain:make-alert-record
             :id "a3" :severity :warning :title "Snoozed" :message "Known issue"
             :source "monitor" :fired-at 999000
             :acknowledged-p nil :snoozed-until 1100000))
   :last-sync-at 999950
   :sync-token "tok-1"))

;;; ============================================================
;;; Format helpers
;;; ============================================================

(define-test format-tokens-test
    :parent tui-provider-suite
  (is string= "0" (orrery/provider:format-tokens 0))
  (is string= "999" (orrery/provider:format-tokens 999))
  (is string= "1.0K" (orrery/provider:format-tokens 1000))
  (is string= "5.0K" (orrery/provider:format-tokens 5000))
  (is string= "12.0K" (orrery/provider:format-tokens 12000))
  (is string= "1.0M" (orrery/provider:format-tokens 1000000))
  (is string= "1.5M" (orrery/provider:format-tokens 1500000)))

(define-test format-cost-cents-test
    :parent tui-provider-suite
  (is string= "0¢" (orrery/provider:format-cost-cents 0))
  (is string= "50¢" (orrery/provider:format-cost-cents 50))
  (is string= "99¢" (orrery/provider:format-cost-cents 99))
  (is string= "$1.00" (orrery/provider:format-cost-cents 100))
  (is string= "$12.50" (orrery/provider:format-cost-cents 1250)))

(define-test format-age-test
    :parent tui-provider-suite
  (is string= "0s" (orrery/provider:format-age 0))
  (is string= "30s" (orrery/provider:format-age 30))
  (is string= "5m" (orrery/provider:format-age 300))
  (is string= "2h" (orrery/provider:format-age 7200))
  (is string= "3d" (orrery/provider:format-age 259200)))

(define-test format-interval-test
    :parent tui-provider-suite
  (is string= "30s" (orrery/provider:format-interval 30))
  (is string= "5m0s" (orrery/provider:format-interval 300))
  (is string= "1h0m" (orrery/provider:format-interval 3600))
  (is string= "1h30m" (orrery/provider:format-interval 5400)))

;;; ============================================================
;;; Session queries
;;; ============================================================

(define-test query-sessions-basic
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (page (orrery/provider:query-sessions store :now *test-now*)))
    ;; All 3 sessions returned
    (is = 3 (orrery/provider:page-total page))
    (is = 3 (length (orrery/provider:page-items page)))
    ;; Default sort is updated-at descending → s1 first (999900)
    (let ((first-view (first (orrery/provider:page-items page))))
      (is string= "s1" (orrery/domain:sr-id (orrery/provider:sv-record first-view)))
      (is = 100 (orrery/provider:sv-age-seconds first-view))
      (is string= "5.0K" (orrery/provider:sv-token-display first-view))
      (is string= "50¢" (orrery/provider:sv-cost-display first-view)))))

(define-test query-sessions-filter-by-status
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (filters (list (orrery/provider:make-filter-spec
                         :field #'orrery/domain:sr-status :op :eq :value :active)))
         (page (orrery/provider:query-sessions store :filters filters :now *test-now*)))
    (is = 2 (orrery/provider:page-total page))
    (true (every (lambda (v)
                   (eq :active (orrery/domain:sr-status (orrery/provider:sv-record v))))
                 (orrery/provider:page-items page)))))

(define-test query-sessions-filter-contains
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (filters (list (orrery/provider:make-filter-spec
                         :field #'orrery/domain:sr-agent-name :op :contains :value "gen")))
         (page (orrery/provider:query-sessions store :filters filters :now *test-now*)))
    (is = 2 (orrery/provider:page-total page))))

(define-test query-sessions-pagination
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (page (orrery/provider:query-sessions store :offset 0 :limit 2 :now *test-now*)))
    (is = 3 (orrery/provider:page-total page))
    (is = 2 (length (orrery/provider:page-items page)))
    (is = 0 (orrery/provider:page-offset page))
    ;; Page 2
    (let ((p2 (orrery/provider:query-sessions store :offset 2 :limit 2 :now *test-now*)))
      (is = 3 (orrery/provider:page-total p2))
      (is = 1 (length (orrery/provider:page-items p2))))))

(define-test query-sessions-custom-sort
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (sort (orrery/provider:make-sort-spec
                :key #'orrery/domain:sr-total-tokens :direction :ascending))
         (page (orrery/provider:query-sessions store :sort sort :now *test-now*)))
    ;; Ascending by tokens: 1500, 5000, 12000
    (is = 1500 (orrery/domain:sr-total-tokens
                (orrery/provider:sv-record (first (orrery/provider:page-items page)))))))

;;; ============================================================
;;; Cron queries
;;; ============================================================

(define-test query-cron-basic
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (page (orrery/provider:query-cron-jobs store :now *test-now*)))
    (is = 3 (orrery/provider:page-total page))
    ;; sync-data is overdue (next-run-at 999600 < now 1000000) and has error
    (let ((sync-view (find "sync-data" (orrery/provider:page-items page)
                           :key (lambda (v) (orrery/domain:cr-name (orrery/provider:cv-record v)))
                           :test #'string=)))
      (true (orrery/provider:cv-overdue-p sync-view))
      (true (orrery/provider:cv-error-p sync-view)))
    ;; cleanup is paused, not overdue
    (let ((cleanup-view (find "cleanup" (orrery/provider:page-items page)
                              :key (lambda (v) (orrery/domain:cr-name (orrery/provider:cv-record v)))
                              :test #'string=)))
      (false (orrery/provider:cv-overdue-p cleanup-view)))))

;;; ============================================================
;;; Health queries
;;; ============================================================

(define-test query-health-basic
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (page (orrery/provider:query-health store)))
    (is = 3 (orrery/provider:page-total page))
    ;; adapter is degraded
    (let ((adapter-view (find "adapter" (orrery/provider:page-items page)
                              :key (lambda (v) (orrery/domain:hr-component (orrery/provider:hv-record v)))
                              :test #'string=)))
      (false (orrery/provider:hv-ok-p adapter-view))
      (is string= "250ms" (orrery/provider:hv-latency-display adapter-view)))))

;;; ============================================================
;;; Event queries
;;; ============================================================

(define-test query-events-basic
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (page (orrery/provider:query-events store :now *test-now*)))
    (is = 3 (orrery/provider:page-total page))
    ;; Default sort descending by timestamp → e3 first
    (let ((first-view (first (orrery/provider:page-items page))))
      (is string= "e3" (orrery/domain:er-id (orrery/provider:ev-record first-view)))
      (is string= "!!" (orrery/provider:ev-severity-indicator first-view))
      (is = 200 (orrery/provider:ev-age-seconds first-view)))))

(define-test query-events-filter-by-kind
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (filters (list (orrery/provider:make-filter-spec
                         :field #'orrery/domain:er-kind :op :eq :value :error)))
         (page (orrery/provider:query-events store :filters filters :now *test-now*)))
    (is = 1 (orrery/provider:page-total page))))

;;; ============================================================
;;; Alert queries
;;; ============================================================

(define-test query-alerts-basic
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (page (orrery/provider:query-alerts store :now *test-now*)))
    (is = 3 (orrery/provider:page-total page))
    ;; a1 is active + critical
    (let ((a1-view (find "a1" (orrery/provider:page-items page)
                         :key (lambda (v) (orrery/domain:ar-id (orrery/provider:alv-record v)))
                         :test #'string=)))
      (true (orrery/provider:alv-active-p a1-view))
      (is eq :critical (orrery/provider:alv-urgency a1-view)))
    ;; a2 is acknowledged → not active
    (let ((a2-view (find "a2" (orrery/provider:page-items page)
                         :key (lambda (v) (orrery/domain:ar-id (orrery/provider:alv-record v)))
                         :test #'string=)))
      (false (orrery/provider:alv-active-p a2-view))
      (is eq :none (orrery/provider:alv-urgency a2-view)))
    ;; a3 is snoozed → not active
    (let ((a3-view (find "a3" (orrery/provider:page-items page)
                         :key (lambda (v) (orrery/domain:ar-id (orrery/provider:alv-record v)))
                         :test #'string=)))
      (false (orrery/provider:alv-active-p a3-view)))))

;;; ============================================================
;;; Usage queries
;;; ============================================================

(define-test query-usage-basic
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (page (orrery/provider:query-usage store)))
    (is = 2 (orrery/provider:page-total page))
    ;; Default sort descending by total-tokens → opus first
    (let ((first-view (first (orrery/provider:page-items page))))
      (is string= "5.0K" (orrery/provider:uv-token-display first-view))
      (is string= "50¢" (orrery/provider:uv-cost-display first-view)))))

;;; ============================================================
;;; Dashboard summary
;;; ============================================================

(define-test dashboard-summary-test
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (ds (orrery/provider:build-dashboard-summary store :now *test-now*)))
    (is = 3 (orrery/provider:ds-session-count ds))
    (is = 2 (orrery/provider:ds-active-session-count ds))
    (is = 3 (orrery/provider:ds-cron-count ds))
    (is = 1 (orrery/provider:ds-overdue-cron-count ds))
    (false (orrery/provider:ds-health-ok-p ds))
    (is = 1 (length (orrery/provider:ds-degraded-components ds)))
    (is string= "adapter" (first (orrery/provider:ds-degraded-components ds)))
    ;; Only a1 is active (a2 acknowledged, a3 snoozed)
    (is = 1 (orrery/provider:ds-alert-count ds))
    (is = 1 (orrery/provider:ds-critical-alert-count ds))
    (is = 6500 (orrery/provider:ds-total-tokens ds))
    (is = 65 (orrery/provider:ds-total-cost-cents ds))))

(define-test dashboard-summary-ui-message-test
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (summary (orrery/provider:build-dashboard-summary store :now *test-now*))
         (msg (orrery/provider:dashboard-summary-ui-message summary :timestamp 1234 :sequence 9)))
    (is string= "tui-status-1234-9" (orrery/adapter:uim-id msg))
    (is eq :tui (orrery/adapter:uim-surface msg))
    (is eq :status (orrery/adapter:uim-kind msg))
    (true (search "deterministic_key" (orrery/adapter:ui-message->json msg)))))

;;; ============================================================
;;; Edge cases
;;; ============================================================

(define-test empty-store-queries
    :parent tui-provider-suite
  (let* ((store (orrery/store:make-sync-store))
         (sp (orrery/provider:query-sessions store :now *test-now*))
         (cp (orrery/provider:query-cron-jobs store :now *test-now*))
         (hp (orrery/provider:query-health store))
         (ep (orrery/provider:query-events store :now *test-now*))
         (ap (orrery/provider:query-alerts store :now *test-now*))
         (up (orrery/provider:query-usage store))
         (ds (orrery/provider:build-dashboard-summary store :now *test-now*)))
    (is = 0 (orrery/provider:page-total sp))
    (is = 0 (orrery/provider:page-total cp))
    (is = 0 (orrery/provider:page-total hp))
    (is = 0 (orrery/provider:page-total ep))
    (is = 0 (orrery/provider:page-total ap))
    (is = 0 (orrery/provider:page-total up))
    (is = 0 (orrery/provider:ds-session-count ds))
    (true (orrery/provider:ds-health-ok-p ds))))

(define-test pagination-beyond-bounds
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (page (orrery/provider:query-sessions store :offset 100 :limit 50 :now *test-now*)))
    (is = 3 (orrery/provider:page-total page))
    (is = 0 (length (orrery/provider:page-items page)))))

(define-test multiple-filters-combine
    :parent tui-provider-suite
  (let* ((store (make-test-store))
         (filters (list
                   (orrery/provider:make-filter-spec
                    :field #'orrery/domain:sr-status :op :eq :value :active)
                   (orrery/provider:make-filter-spec
                    :field #'orrery/domain:sr-total-tokens :op :gt :value 10000)))
         (page (orrery/provider:query-sessions store :filters filters :now *test-now*)))
    ;; Only s3: active + 12000 tokens
    (is = 1 (orrery/provider:page-total page))
    (is string= "s3" (orrery/domain:sr-id
                       (orrery/provider:sv-record (first (orrery/provider:page-items page)))))))
