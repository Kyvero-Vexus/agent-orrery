;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; harness-tests.lisp — Parachute tests for the fixture runtime harness
;;;

(in-package #:orrery/harness-tests)

;;; ============================================================
;;; Clock Tests
;;; ============================================================

(define-test clock-tests)

(define-test (clock-tests clock-creation)
  (let ((c (make-fixture-clock)))
    (is = 3920000000 (clock-now c))))

(define-test (clock-tests clock-custom-start)
  (let ((c (make-fixture-clock :start-time 1000)))
    (is = 1000 (clock-now c))))

(define-test (clock-tests clock-advance)
  (let ((c (make-fixture-clock :start-time 1000)))
    (let ((new-time (clock-advance! c 500)))
      (is = 1500 new-time)
      (is = 1500 (clock-now c)))))

(define-test (clock-tests clock-set)
  (let ((c (make-fixture-clock)))
    (clock-set! c 9999)
    (is = 9999 (clock-now c))))

(define-test (clock-tests clock-monotonicity)
  (let ((c (make-fixture-clock :start-time 0)))
    (dotimes (i 100)
      (let ((before (clock-now c)))
        (clock-advance! c 1)
        (true (> (clock-now c) before))))))

;;; ============================================================
;;; Timeline Tests
;;; ============================================================

(define-test timeline-tests)

(define-test (timeline-tests empty-timeline)
  (let ((tl (make-timeline)))
    (is = 0 (timeline-pending-count tl))))

(define-test (timeline-tests schedule-and-count)
  (let ((tl (make-timeline)))
    (timeline-schedule tl 100 (lambda () nil))
    (timeline-schedule tl 200 (lambda () nil))
    (is = 2 (timeline-pending-count tl))))

(define-test (timeline-tests run-until-executes-in-order)
  (let ((tl (make-timeline))
        (c (make-fixture-clock :start-time 0))
        (log nil))
    (timeline-schedule tl 30 (lambda () (push :third log)))
    (timeline-schedule tl 10 (lambda () (push :first log)))
    (timeline-schedule tl 20 (lambda () (push :second log)))
    (let ((count (timeline-run-until! tl c 50)))
      (is = 3 count)
      (is equal '(:third :second :first) log)
      (is = 50 (clock-now c))
      (is = 0 (timeline-pending-count tl)))))

(define-test (timeline-tests run-until-partial)
  (let ((tl (make-timeline))
        (c (make-fixture-clock :start-time 0))
        (executed 0))
    (timeline-schedule tl 10 (lambda () (incf executed)))
    (timeline-schedule tl 20 (lambda () (incf executed)))
    (timeline-schedule tl 30 (lambda () (incf executed)))
    (timeline-run-until! tl c 25)
    (is = 2 executed)
    (is = 1 (timeline-pending-count tl))
    (is = 25 (clock-now c))))

(define-test (timeline-tests run-until-empty)
  (let ((tl (make-timeline))
        (c (make-fixture-clock :start-time 0)))
    (let ((count (timeline-run-until! tl c 100)))
      (is = 0 count)
      (is = 100 (clock-now c)))))

;;; ============================================================
;;; Generator Determinism Tests
;;; ============================================================

(define-test generator-tests)

(defun records-equal-p (list-a list-b &key (key #'identity) (test #'string=))
  "Check that two lists of records have equal keys."
  (and (= (length list-a) (length list-b))
       (every (lambda (a b) (funcall test (funcall key a) (funcall key b)))
              list-a list-b)))

(define-test (generator-tests sessions-deterministic)
  (let* ((c1 (make-fixture-clock :start-time 3920000000))
         (c2 (make-fixture-clock :start-time 3920000000))
         (s1 (generate-sessions c1))
         (s2 (generate-sessions c2)))
    (is = (length s1) (length s2))
    (true (records-equal-p s1 s2 :key #'sr-id))))

(define-test (generator-tests cron-deterministic)
  (let* ((c1 (make-fixture-clock))
         (c2 (make-fixture-clock))
         (j1 (generate-cron-jobs c1))
         (j2 (generate-cron-jobs c2)))
    (true (records-equal-p j1 j2 :key #'cr-name))))

(define-test (generator-tests health-deterministic)
  (let* ((c1 (make-fixture-clock))
         (c2 (make-fixture-clock))
         (h1 (generate-health-checks c1))
         (h2 (generate-health-checks c2)))
    (true (records-equal-p h1 h2 :key #'hr-component))))

(define-test (generator-tests usage-deterministic)
  (let* ((c1 (make-fixture-clock))
         (c2 (make-fixture-clock))
         (u1 (generate-usage-records c1))
         (u2 (generate-usage-records c2)))
    (is = (length u1) (length u2))
    (true (every (lambda (a b)
                   (and (string= (ur-model a) (ur-model b))
                        (= (ur-total-tokens a) (ur-total-tokens b))))
                 u1 u2))))

(define-test (generator-tests events-deterministic)
  (let* ((c1 (make-fixture-clock))
         (c2 (make-fixture-clock))
         (e1 (generate-events c1))
         (e2 (generate-events c2)))
    (true (records-equal-p e1 e2 :key #'er-id))))

(define-test (generator-tests alerts-deterministic)
  (let* ((c1 (make-fixture-clock))
         (c2 (make-fixture-clock))
         (a1 (generate-alerts c1))
         (a2 (generate-alerts c2)))
    (true (records-equal-p a1 a2 :key #'ar-id))))

(define-test (generator-tests subagents-deterministic)
  (let* ((c1 (make-fixture-clock))
         (c2 (make-fixture-clock))
         (r1 (generate-subagent-runs c1))
         (r2 (generate-subagent-runs c2)))
    (true (records-equal-p r1 r2 :key #'sar-id))))

(define-test (generator-tests session-count)
  (let ((c (make-fixture-clock)))
    (is = 5 (length (generate-sessions c)))
    (is = 10 (length (generate-sessions c :count 10)))))

;;; ============================================================
;;; Fixture Adapter Tests
;;; ============================================================

(define-test adapter-tests)

(define-test (adapter-tests list-sessions)
  (let ((a (make-fixture-adapter)))
    (let ((sessions (adapter-list-sessions a)))
      (is = 5 (length sessions))
      (true (every #'session-record-p sessions))
      (is string= "session-001" (sr-id (first sessions))))))

(define-test (adapter-tests session-history-typed)
  "Session history returns HISTORY-ENTRY structs, not plists."
  (let ((a (make-fixture-adapter)))
    (let ((history (adapter-session-history a "session-001")))
      (true (listp history))
      (true (plusp (length history)))
      (true (every #'history-entry-p history))
      ;; First message is from :user
      (is eq :user (he-role (first history)))
      ;; Each entry has a positive token-count
      (true (every (lambda (h) (plusp (he-token-count h))) history)))))

(define-test (adapter-tests session-history-missing)
  (let ((a (make-fixture-adapter)))
    (is eq nil (adapter-session-history a "nonexistent"))))

(define-test (adapter-tests list-cron-jobs)
  (let ((a (make-fixture-adapter)))
    (let ((jobs (adapter-list-cron-jobs a)))
      (is = 3 (length jobs))
      (true (every #'cron-record-p jobs)))))

(define-test (adapter-tests trigger-cron)
  (let ((a (make-fixture-adapter)))
    (let* ((job-name "cron-001")
           (job (find job-name (fixture-cron-jobs a)
                      :key #'cr-name :test #'string=))
           (old-run-count (cr-run-count job)))
      (true (adapter-trigger-cron a job-name))
      (is = (1+ old-run-count) (cr-run-count job)))))

(define-test (adapter-tests trigger-cron-missing)
  "Triggering a nonexistent cron job signals ADAPTER-NOT-FOUND."
  (let ((a (make-fixture-adapter)))
    (fail (adapter-trigger-cron a "nonexistent") adapter-not-found)))

(define-test (adapter-tests pause-resume-cron)
  "Pause and resume a cron job, verifying status transitions."
  (let ((a (make-fixture-adapter)))
    (let ((job (find "cron-001" (fixture-cron-jobs a)
                     :key #'cr-name :test #'string=)))
      ;; Pause
      (true (adapter-pause-cron a "cron-001"))
      (is eq :paused (cr-status job))
      ;; Resume
      (true (adapter-resume-cron a "cron-001"))
      (is eq :active (cr-status job)))))

(define-test (adapter-tests pause-cron-missing)
  (let ((a (make-fixture-adapter)))
    (fail (adapter-pause-cron a "nonexistent") adapter-not-found)))

(define-test (adapter-tests system-health)
  (let ((a (make-fixture-adapter)))
    (let ((health (adapter-system-health a)))
      (is = 3 (length health))
      (true (every #'health-record-p health))
      (is string= "gateway" (hr-component (first health))))))

(define-test (adapter-tests usage-records-filter)
  (let ((a (make-fixture-adapter)))
    ;; All generated records are :hourly
    (let ((hourly (adapter-usage-records a :period :hourly)))
      (true (plusp (length hourly)))
      (true (every (lambda (r) (eq :hourly (ur-period r))) hourly)))
    ;; No daily records generated
    (let ((daily (adapter-usage-records a :period :daily)))
      (is = 0 (length daily)))))

(define-test (adapter-tests tail-events)
  (let ((a (make-fixture-adapter)))
    (let ((all-events (adapter-tail-events a :since 0 :limit 100)))
      (is = 20 (length all-events)))
    ;; With limit
    (let ((limited (adapter-tail-events a :since 0 :limit 5)))
      (is = 5 (length limited)))))

(define-test (adapter-tests list-alerts)
  (let ((a (make-fixture-adapter)))
    (let ((alerts (adapter-list-alerts a)))
      (is = 2 (length alerts))
      (true (every #'alert-record-p alerts)))))

(define-test (adapter-tests acknowledge-alert)
  (let ((a (make-fixture-adapter)))
    (let ((alert (first (fixture-alerts a))))
      (false (ar-acknowledged-p alert))
      (true (adapter-acknowledge-alert a (ar-id alert)))
      (true (ar-acknowledged-p alert)))))

(define-test (adapter-tests acknowledge-alert-missing)
  (let ((a (make-fixture-adapter)))
    (fail (adapter-acknowledge-alert a "nonexistent") adapter-not-found)))

(define-test (adapter-tests snooze-alert)
  "Snooze an alert and verify snoozed-until is set."
  (let ((a (make-fixture-adapter)))
    (let* ((alert (first (fixture-alerts a)))
           (now   (clock-now (fixture-adapter-clock a))))
      (false (ar-snoozed-until alert))
      (true (adapter-snooze-alert a (ar-id alert) 3600))
      (is = (+ now 3600) (ar-snoozed-until alert)))))

(define-test (adapter-tests snooze-alert-missing)
  (let ((a (make-fixture-adapter)))
    (fail (adapter-snooze-alert a "nonexistent" 3600) adapter-not-found)))

(define-test (adapter-tests list-subagents)
  (let ((a (make-fixture-adapter)))
    (let ((subs (adapter-list-subagents a)))
      (is = 3 (length subs))
      (true (every #'subagent-record-p subs)))))

;;; ============================================================
;;; Capability Introspection Tests
;;; ============================================================

(define-test capability-tests)

(define-test (capability-tests capabilities-returned)
  "adapter-capabilities returns a list of adapter-capability structs."
  (let* ((a (make-fixture-adapter))
         (caps (adapter-capabilities a)))
    (true (listp caps))
    (true (plusp (length caps)))
    (true (every #'adapter-capability-p caps))))

(define-test (capability-tests fixture-supports-all)
  "Fixture adapter reports all standard capabilities as supported."
  (let* ((a (make-fixture-adapter))
         (caps (adapter-capabilities a)))
    (dolist (name '("trigger-cron" "pause-cron" "acknowledge-alert"
                    "snooze-alert" "session-history"))
      (let ((cap (find name caps :key #'cap-name :test #'string=)))
        (true cap)
        (true (cap-supported-p cap))))))

;;; ============================================================
;;; Adapter Conformance Suite Tests
;;; ============================================================

(define-test conformance-tests)

(define-test (conformance-tests fixture-passes-conformance)
  "The fixture adapter passes the full conformance suite."
  (let ((a (make-fixture-adapter)))
    (multiple-value-bind (passed-p failures)
        (run-adapter-conformance a)
      (true passed-p)
      (is = 0 (length failures)))))

;;; ============================================================
;;; Full Scenario Replay
;;; ============================================================

(define-test scenario-tests)

(define-test (scenario-tests full-replay)
  "Create an adapter, advance through a scripted scenario, verify final state."
  (let* ((clk (make-fixture-clock :start-time 3920000000))
         (adapter (make-fixture-adapter :clock clk))
         (tl (fixture-adapter-timeline adapter)))
    ;; Initial state checks
    (is = 5 (length (adapter-list-sessions adapter)))
    (is = 2 (length (adapter-list-alerts adapter)))
    (false (ar-acknowledged-p (first (fixture-alerts adapter))))

    ;; Schedule some scenario events
    ;; At T+100: a new session gets more tokens
    (let ((s1 (first (fixture-sessions adapter))))
      (timeline-schedule tl (+ 3920000000 100)
                         (lambda ()
                           (incf (sr-total-tokens s1) 500)
                           (incf (sr-message-count s1) 3))))

    ;; At T+200: acknowledge first alert
    (timeline-schedule tl (+ 3920000000 200)
                       (lambda ()
                         (adapter-acknowledge-alert adapter "alert-001")))

    ;; At T+300: trigger a cron job
    (timeline-schedule tl (+ 3920000000 300)
                       (lambda ()
                         (adapter-trigger-cron adapter "cron-001")))

    ;; Run the scenario
    (let ((executed (timeline-run-until! tl clk (+ 3920000000 500))))
      ;; 3 scheduled + 1 from trigger-cron completion = 4
      (is = 4 executed))

    ;; Verify final state
    (let ((s1 (first (fixture-sessions adapter))))
      (is = (+ 1500 500) (sr-total-tokens s1))
      (is = (+ 10 3) (sr-message-count s1)))

    ;; Alert acknowledged
    (true (ar-acknowledged-p
           (find "alert-001" (fixture-alerts adapter)
                 :key #'ar-id :test #'string=)))

    ;; Cron job was triggered
    (let ((job (find "cron-001" (fixture-cron-jobs adapter)
                     :key #'cr-name :test #'string=)))
      (is = 6 (cr-run-count job)))

    ;; Clock advanced
    (is = (+ 3920000000 500) (clock-now clk))))

(define-test (scenario-tests pause-resume-in-timeline)
  "Scenario: pause a cron job, advance time, resume it."
  (let* ((clk (make-fixture-clock :start-time 3920000000))
         (adapter (make-fixture-adapter :clock clk))
         (tl (fixture-adapter-timeline adapter)))

    ;; At T+50: pause cron-001
    (timeline-schedule tl (+ 3920000000 50)
                       (lambda ()
                         (adapter-pause-cron adapter "cron-001")))
    ;; At T+150: resume cron-001
    (timeline-schedule tl (+ 3920000000 150)
                       (lambda ()
                         (adapter-resume-cron adapter "cron-001")))

    ;; Run to T+100 — pause should have fired
    (timeline-run-until! tl clk (+ 3920000000 100))
    (let ((job (find "cron-001" (fixture-cron-jobs adapter)
                     :key #'cr-name :test #'string=)))
      (is eq :paused (cr-status job)))

    ;; Run to T+200 — resume should have fired
    (timeline-run-until! tl clk (+ 3920000000 200))
    (let ((job (find "cron-001" (fixture-cron-jobs adapter)
                     :key #'cr-name :test #'string=)))
      (is eq :active (cr-status job)))))
