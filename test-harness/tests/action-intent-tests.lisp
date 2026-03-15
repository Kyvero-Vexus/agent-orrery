;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; action-intent-tests.lisp — Tests for action-intent algebra (3st)
;;;

(in-package #:orrery/harness-tests)

(define-test action-intent)

;;; ─── Intent Construction ───

(define-test (action-intent construct-list-sessions)
  (let ((i (intent-list-sessions)))
    (true (action-intent-p i))
    (is eq :list-sessions (ai-kind i))
    (is eq nil (ai-target-id i))
    (is eq nil (ai-params i))))

(define-test (action-intent construct-session-history)
  (let ((i (intent-session-history "sess-42")))
    (is eq :session-history (ai-kind i))
    (is string= "sess-42" (ai-target-id i))))

(define-test (action-intent construct-list-cron-jobs)
  (let ((i (intent-list-cron-jobs)))
    (is eq :list-cron-jobs (ai-kind i))))

(define-test (action-intent construct-system-health)
  (let ((i (intent-system-health)))
    (is eq :system-health (ai-kind i))))

(define-test (action-intent construct-list-alerts)
  (let ((i (intent-list-alerts)))
    (is eq :list-alerts (ai-kind i))))

(define-test (action-intent construct-list-subagents)
  (let ((i (intent-list-subagents)))
    (is eq :list-subagents (ai-kind i))))

(define-test (action-intent construct-capabilities)
  (let ((i (intent-capabilities)))
    (is eq :capabilities (ai-kind i))))

(define-test (action-intent construct-trigger-cron)
  (let ((i (intent-trigger-cron "daily-backup")))
    (is eq :trigger-cron (ai-kind i))
    (is string= "daily-backup" (ai-target-id i))))

(define-test (action-intent construct-pause-cron)
  (let ((i (intent-pause-cron "job-x")))
    (is eq :pause-cron (ai-kind i))
    (is string= "job-x" (ai-target-id i))))

(define-test (action-intent construct-resume-cron)
  (let ((i (intent-resume-cron "job-y")))
    (is eq :resume-cron (ai-kind i))
    (is string= "job-y" (ai-target-id i))))

(define-test (action-intent construct-acknowledge-alert)
  (let ((i (intent-acknowledge-alert "alert-7")))
    (is eq :acknowledge-alert (ai-kind i))
    (is string= "alert-7" (ai-target-id i))))

(define-test (action-intent construct-snooze-alert)
  (let ((i (intent-snooze-alert "alert-9" 7200)))
    (is eq :snooze-alert (ai-kind i))
    (is string= "alert-9" (ai-target-id i))
    (is = 7200 (getf (ai-params i) :duration-seconds))))

(define-test (action-intent construct-usage-records)
  (let ((i (intent-usage-records :period "daily")))
    (is eq :usage-records (ai-kind i))
    (is string= "daily" (getf (ai-params i) :period))))

(define-test (action-intent construct-usage-records-no-period)
  (let ((i (intent-usage-records)))
    (is eq :usage-records (ai-kind i))
    (is eq nil (ai-params i))))

(define-test (action-intent construct-tail-events)
  (let ((i (intent-tail-events :since 1000 :limit 50)))
    (is eq :tail-events (ai-kind i))
    (is = 1000 (getf (ai-params i) :since))
    (is = 50 (getf (ai-params i) :limit))))

(define-test (action-intent construct-tail-events-defaults)
  (let ((i (intent-tail-events)))
    (is eq :tail-events (ai-kind i))
    (is eq nil (ai-params i))))

;;; ─── Intent Category ───

(define-test (action-intent category-queries)
  (dolist (kind '(:list-sessions :session-history :list-cron-jobs :system-health
                  :usage-records :tail-events :list-alerts :list-subagents :capabilities))
    (let ((i (make-action-intent :kind kind)))
      (is eq :query (intent-category i)))))

(define-test (action-intent category-commands)
  (dolist (kind '(:trigger-cron :pause-cron :resume-cron
                  :acknowledge-alert :snooze-alert))
    (let ((i (make-action-intent :kind kind)))
      (is eq :command (intent-category i)))))

;;; ─── Describe Intent ───

(define-test (action-intent describe-list-sessions)
  (is string= "List active sessions"
      (describe-intent (intent-list-sessions))))

(define-test (action-intent describe-session-history)
  (true (search "sess-1"
                (describe-intent (intent-session-history "sess-1")))))

(define-test (action-intent describe-trigger-cron)
  (true (search "daily-job"
                (describe-intent (intent-trigger-cron "daily-job")))))

(define-test (action-intent describe-acknowledge-alert)
  (true (search "alert-5"
                (describe-intent (intent-acknowledge-alert "alert-5")))))

(define-test (action-intent describe-snooze-alert)
  (true (search "alert-99"
                (describe-intent (intent-snooze-alert "alert-99" 300)))))

;;; ─── Interpret via Fixture Adapter ───

(define-test (action-intent interpret-list-sessions-fixture)
  (let* ((adapter (make-fixture-adapter))
         (result (interpret-intent adapter (intent-list-sessions))))
    (true (intent-result-p result))
    (is eq :ok (ir-status result))
    (true (listp (ir-payload result)))
    (true (> (length (ir-payload result)) 0))))

(define-test (action-intent interpret-list-cron-fixture)
  (let* ((adapter (make-fixture-adapter))
         (result (interpret-intent adapter (intent-list-cron-jobs))))
    (is eq :ok (ir-status result))
    (true (listp (ir-payload result)))
    (true (> (length (ir-payload result)) 0))))

(define-test (action-intent interpret-system-health-fixture)
  (let* ((adapter (make-fixture-adapter))
         (result (interpret-intent adapter (intent-system-health))))
    (is eq :ok (ir-status result))
    (true (listp (ir-payload result)))
    (true (> (length (ir-payload result)) 0))))

(define-test (action-intent interpret-list-alerts-fixture)
  (let* ((adapter (make-fixture-adapter))
         (result (interpret-intent adapter (intent-list-alerts))))
    (is eq :ok (ir-status result))
    (true (listp (ir-payload result)))
    (true (> (length (ir-payload result)) 0))))

(define-test (action-intent interpret-capabilities-fixture)
  (let* ((adapter (make-fixture-adapter))
         (result (interpret-intent adapter (intent-capabilities))))
    (is eq :ok (ir-status result))
    (true (listp (ir-payload result)))))

;;; ─── Batch Interpretation ───

(define-test (action-intent batch-interpret)
  (let* ((adapter (make-fixture-adapter))
         (intents (list (intent-list-sessions)
                        (intent-system-health)
                        (intent-capabilities)))
         (results (interpret-intents adapter intents)))
    (is = 3 (length results))
    (is eq :ok (ir-status (first results)))
    (is eq :ok (ir-status (second results)))
    (is eq :ok (ir-status (third results)))))

;;; ─── Result carries intent reference ───

(define-test (action-intent result-carries-intent)
  (let* ((adapter (make-fixture-adapter))
         (intent (intent-list-sessions))
         (result (interpret-intent adapter intent)))
    (is eq intent (ir-intent result))))

;;; ─── Intent struct equality / pure value semantics ───

(define-test (action-intent pure-value-semantics)
  (let ((i1 (intent-list-sessions))
        (i2 (intent-list-sessions)))
    (is eq (ai-kind i1) (ai-kind i2))
    (is eq (ai-target-id i1) (ai-target-id i2))))
