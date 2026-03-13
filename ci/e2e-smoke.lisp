;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; e2e-smoke.lisp — Epic 1 E2E Gate: Fixture smoke scenarios
;;;
;;; Runs foundational E2E smoke tests against the fixture runtime,
;;; proving the data layer can serve all scenario requirements S1-S6.
;;;
;;; Produces a structured artifact log to stdout.
;;;
;;; Exit codes:
;;;   0 — all scenarios passed
;;;   1 — one or more scenarios failed
;;;   2 — load error

(require :asdf)

(dolist (path (list #P"/home/slime/projects/agent-orrery/"
                    (truename ".")))
  (pushnew path asdf:*central-registry* :test #'equal))
(asdf:clear-source-registry)

(handler-case
    (ql:quickload :agent-orrery/test-harness :silent t)
  (error (e)
    (format *error-output* "~&LOAD ERROR: ~A~%" e)
    (sb-ext:exit :code 2)))

;;; ============================================================
;;; Framework
;;; ============================================================

(defvar *scenario-results* '())
(defvar *current-scenario* nil)

(defmacro define-scenario (id title &body body)
  `(progn
     (setf *current-scenario* ,id)
     (format t "~&~%━━━ Scenario ~A: ~A ━━━~%" ,id ,title)
     (handler-case
         (let ((checks 0) (passed 0))
           (flet ((check (description result)
                    (incf checks)
                    (if result
                        (progn (incf passed)
                               (format t "  ✔ ~A~%" description))
                        (format t "  ✘ ~A~%" description))))
             ,@body
             (let ((ok (= checks passed)))
               (push (list :id ,id :title ,title
                           :checks checks :passed passed :ok ok)
                     *scenario-results*)
               (format t "  ── ~D/~D checks passed~%" passed checks))))
       (error (e)
         (format t "  ✘ SCENARIO ERROR: ~A~%" e)
         (push (list :id ,id :title ,title
                     :checks 0 :passed 0 :ok nil :error (princ-to-string e))
               *scenario-results*)))))

;;; ============================================================
;;; Setup: create fixture adapter with timeline
;;; ============================================================

(defvar *clock* (orrery/harness:make-fixture-clock))
(defvar *adapter* (orrery/harness:make-fixture-adapter :clock *clock*))

(format t "~&══════════════════════════════════════════════════════════~%")
(format t "  Agent Orrery — Epic 1 E2E Smoke (Fixture Runtime)~%")
(format t "══════════════════════════════════════════════════════════~%")
(format t "~&Clock epoch: ~D~%" (orrery/harness:clock-now *clock*))
(format t "Adapter type: ~A~%" (type-of *adapter*))

;;; ============================================================
;;; S1: Health + Session Snapshot
;;; ============================================================

(define-scenario "S1" "Health + Session Snapshot"
  ;; Verify gateway health card
  (let ((health (orrery/adapter:adapter-system-health *adapter*)))
    (check "system-health returns non-empty list"
           (plusp (length health)))
    (check "gateway component present"
           (find "gateway" health
                 :key #'orrery/domain:hr-component :test #'string=))
    (check "all components report :ok"
           (every (lambda (h) (eq :ok (orrery/domain:hr-status h))) health))
    (check "latency-ms is non-negative"
           (every (lambda (h) (>= (orrery/domain:hr-latency-ms h) 0)) health)))

  ;; Verify active session table
  (let ((sessions (orrery/adapter:adapter-list-sessions *adapter*)))
    (check "list-sessions returns non-empty list"
           (plusp (length sessions)))
    (check "all entries are session-record"
           (every #'orrery/domain:session-record-p sessions))
    (check "sessions have non-empty model field"
           (every (lambda (s) (plusp (length (orrery/domain:sr-model s)))) sessions))
    (check "sessions have token counts"
           (every (lambda (s) (>= (orrery/domain:sr-total-tokens s) 0)) sessions))))

;;; ============================================================
;;; S2: Session Drill-Down and History
;;; ============================================================

(define-scenario "S2" "Session Drill-Down and History"
  (let* ((sessions (orrery/adapter:adapter-list-sessions *adapter*))
         (target (first sessions))
         (target-id (orrery/domain:sr-id target)))
    (check "target session exists"
           (not (null target)))

    ;; Open detail — get history
    (let ((history (orrery/adapter:adapter-session-history *adapter* target-id)))
      (check "session-history returns a list"
             (listp history))
      (check "history is non-empty for active session"
             (plusp (length history)))
      (check "history entries are history-entry structs"
             (every #'orrery/domain:history-entry-p history))
      (check "history entries have timestamps"
             (every (lambda (h) (plusp (orrery/domain:he-timestamp h))) history))
      (check "history is chronologically ordered"
             (let ((ts (mapcar #'orrery/domain:he-timestamp history)))
               (equal ts (sort (copy-list ts) #'<))))
      ;; Filter simulation: search for entries containing "Message 1"
      (let ((filtered (remove-if-not
                       (lambda (h)
                         (search "Message 1" (orrery/domain:he-content h)))
                       history)))
        (check "filter/search reduces result set"
               (< (length filtered) (length history)))))))

;;; ============================================================
;;; S3: Cron Operations
;;; ============================================================

(define-scenario "S3" "Cron Operations"
  (let ((jobs (orrery/adapter:adapter-list-cron-jobs *adapter*)))
    (check "list-cron-jobs returns non-empty list"
           (plusp (length jobs)))
    (check "all entries are cron-record"
           (every #'orrery/domain:cron-record-p jobs)))

  ;; Trigger a cron job manually
  (let* ((job-name "cron-001")
         (job (find job-name (orrery/harness:fixture-cron-jobs *adapter*)
                    :key #'orrery/domain:cr-name :test #'string=))
         (old-count (orrery/domain:cr-run-count job)))
    (check "trigger-cron returns T"
           (orrery/adapter:adapter-trigger-cron *adapter* job-name))
    (check "run-count incremented after trigger"
           (= (1+ old-count) (orrery/domain:cr-run-count job)))

    ;; Run timeline to complete the triggered job
    (orrery/harness:timeline-run-until!
     (orrery/harness:fixture-adapter-timeline *adapter*)
     *clock*
     (+ (orrery/harness:clock-now *clock*) 15))
    (check "cron job status is :active after completion"
           (eq :active (orrery/domain:cr-status job))))

  ;; Pause/resume
  (check "pause-cron returns T"
         (orrery/adapter:adapter-pause-cron *adapter* "cron-001"))
  (let ((job (find "cron-001" (orrery/harness:fixture-cron-jobs *adapter*)
                   :key #'orrery/domain:cr-name :test #'string=)))
    (check "status is :paused after pause"
           (eq :paused (orrery/domain:cr-status job))))
  (check "resume-cron returns T"
         (orrery/adapter:adapter-resume-cron *adapter* "cron-001"))
  (let ((job (find "cron-001" (orrery/harness:fixture-cron-jobs *adapter*)
                   :key #'orrery/domain:cr-name :test #'string=)))
    (check "status is :active after resume"
           (eq :active (orrery/domain:cr-status job)))))

;;; ============================================================
;;; S4: Cost + Usage Analytics
;;; ============================================================

(define-scenario "S4" "Cost + Usage Analytics"
  ;; Load usage data
  (let ((hourly (orrery/adapter:adapter-usage-records *adapter* :period :hourly)))
    (check "usage-records returns non-empty list"
           (plusp (length hourly)))
    (check "all entries are usage-record"
           (every #'orrery/domain:usage-record-p hourly))
    (check "all entries have :hourly period"
           (every (lambda (r) (eq :hourly (orrery/domain:ur-period r))) hourly))

    ;; Per-model totals
    (let* ((models (remove-duplicates (mapcar #'orrery/domain:ur-model hourly)
                                      :test #'string=))
           (model-totals (mapcar (lambda (m)
                                   (reduce #'+
                                           (remove-if-not
                                            (lambda (r) (string= m (orrery/domain:ur-model r)))
                                            hourly)
                                           :key #'orrery/domain:ur-total-tokens))
                                 models)))
      (check "multiple models present"
             (> (length models) 1))
      (check "per-model totals are positive"
             (every #'plusp model-totals)))

    ;; Time window simulation: 24h vs last 6h
    (let* ((now (orrery/harness:clock-now *clock*))
           (six-hours-ago (- now (* 6 3600)))
           (recent (remove-if (lambda (r) (< (orrery/domain:ur-timestamp r) six-hours-ago))
                              hourly)))
      (check "time window filtering works (6h < 24h)"
             (< (length recent) (length hourly))))))

;;; ============================================================
;;; S5: Sub-Agent Monitoring
;;; ============================================================

(define-scenario "S5" "Sub-Agent Monitoring"
  (let ((subs (orrery/adapter:adapter-list-subagents *adapter*)))
    (check "list-subagents returns non-empty list"
           (plusp (length subs)))
    (check "all entries are subagent-record"
           (every #'orrery/domain:subagent-record-p subs))
    ;; Verify run details
    (let ((running (remove-if-not
                    (lambda (s) (eq :running (orrery/domain:sar-status s)))
                    subs))
          (completed (remove-if-not
                      (lambda (s) (eq :completed (orrery/domain:sar-status s)))
                      subs)))
      (check "at least one running sub-agent"
             (plusp (length running)))
      (check "at least one completed sub-agent"
             (plusp (length completed)))
      ;; Completed agents have finish time and token count
      (check "completed agents have finished-at"
             (every (lambda (s) (orrery/domain:sar-finished-at s)) completed))
      (check "sub-agents have token counts"
             (every (lambda (s) (>= (orrery/domain:sar-total-tokens s) 0)) subs)))))

;;; ============================================================
;;; S6: Alert Engine
;;; ============================================================

(define-scenario "S6" "Alert Engine"
  (let ((alerts (orrery/adapter:adapter-list-alerts *adapter*)))
    (check "list-alerts returns non-empty list"
           (plusp (length alerts)))
    (check "all entries are alert-record"
           (every #'orrery/domain:alert-record-p alerts))
    (check "alerts have severity"
           (every (lambda (a) (member (orrery/domain:ar-severity a)
                                      '(:info :warning :critical)))
                  alerts)))

  ;; Acknowledge alert
  (let* ((alert (first (orrery/adapter:adapter-list-alerts *adapter*)))
         (alert-id (orrery/domain:ar-id alert)))
    (check "alert is initially unacknowledged"
           (not (orrery/domain:ar-acknowledged-p alert)))
    (check "acknowledge-alert returns T"
           (orrery/adapter:adapter-acknowledge-alert *adapter* alert-id))
    (check "alert is acknowledged after ack"
           (orrery/domain:ar-acknowledged-p alert)))

  ;; Snooze alert
  (let* ((alert (second (orrery/adapter:adapter-list-alerts *adapter*)))
         (alert-id (orrery/domain:ar-id alert))
         (now (orrery/harness:clock-now *clock*)))
    (check "snooze-alert returns T"
           (orrery/adapter:adapter-snooze-alert *adapter* alert-id 3600))
    (check "snoozed-until is set correctly"
           (= (+ now 3600) (orrery/domain:ar-snoozed-until alert))))

  ;; Verify event stream has entries (audit log proxy)
  (let ((events (orrery/adapter:adapter-tail-events *adapter* :since 0 :limit 100)))
    (check "event stream has entries"
           (plusp (length events)))))

;;; ============================================================
;;; Conformance Suite
;;; ============================================================

(define-scenario "CONF" "Adapter Conformance Suite"
  (multiple-value-bind (passed-p failures)
      (orrery/harness:run-adapter-conformance *adapter*)
    (check "conformance suite passes"
           passed-p)
    (check "zero conformance failures"
           (zerop (length failures)))
    (when failures
      (dolist (f failures)
        (format t "    FAIL: ~A~%" f)))))

;;; ============================================================
;;; Capability Introspection
;;; ============================================================

(define-scenario "CAP" "Capability Introspection"
  (let ((caps (orrery/adapter:adapter-capabilities *adapter*)))
    (check "capabilities returned"
           (plusp (length caps)))
    (check "all capabilities are adapter-capability structs"
           (every #'orrery/domain:adapter-capability-p caps))
    (dolist (name '("trigger-cron" "pause-cron" "acknowledge-alert"
                    "snooze-alert" "session-history"))
      (let ((cap (find name caps :key #'orrery/domain:cap-name :test #'string=)))
        (check (format nil "capability '~A' present and supported" name)
               (and cap (orrery/domain:cap-supported-p cap)))))))

;;; ============================================================
;;; Summary
;;; ============================================================

(format t "~&~%══════════════════════════════════════════════════════════~%")
(format t "  SUMMARY~%")
(format t "══════════════════════════════════════════════════════════~%~%")

(let ((total-checks 0)
      (total-passed 0)
      (scenarios-passed 0)
      (scenarios-failed 0))
  (dolist (r (reverse *scenario-results*))
    (let ((id (getf r :id))
          (title (getf r :title))
          (checks (getf r :checks))
          (passed (getf r :passed))
          (ok (getf r :ok)))
      (incf total-checks checks)
      (incf total-passed passed)
      (if ok
          (progn (incf scenarios-passed)
                 (format t "  ✔ ~A: ~A (~D/~D)~%" id title passed checks))
          (progn (incf scenarios-failed)
                 (format t "  ✘ ~A: ~A (~D/~D)~%" id title passed checks)))))

  (format t "~&~%  Scenarios: ~D passed, ~D failed~%"
          scenarios-passed scenarios-failed)
  (format t "  Checks:    ~D/~D passed~%~%" total-passed total-checks)

  (if (zerop scenarios-failed)
      (progn
        (format t "  ══ EPIC 1 E2E GATE: PASSED ══~%")
        (sb-ext:exit :code 0))
      (progn
        (format t "  ══ EPIC 1 E2E GATE: FAILED ══~%")
        (sb-ext:exit :code 1))))
