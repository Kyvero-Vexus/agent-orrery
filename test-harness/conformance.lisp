;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; conformance.lisp — Adapter conformance suite helpers
;;;

(in-package #:orrery/harness)

(declaim (ftype (function (t &key (:exercise-commands boolean)) (values boolean list))
                run-adapter-conformance-suite))
(defun run-adapter-conformance-suite (adapter &key (exercise-commands nil))
  "Run conformance checks against ADAPTER.
Returns (values passed-p failures)."
  (let ((failures '()))
    (flet ((check (description form)
             (unless form
               (push description failures))))
      ;; core reads
      (let ((sessions (adapter-list-sessions adapter)))
        (check "list-sessions returns list" (listp sessions))
        (check "list-sessions typed" (every #'session-record-p sessions))
        (when sessions
          (let ((hist (adapter-session-history adapter (sr-id (first sessions)))))
            (check "session-history returns list" (listp hist))
            (check "session-history typed" (every #'history-entry-p hist)))))

      (let ((cron (adapter-list-cron-jobs adapter)))
        (check "list-cron-jobs returns list" (listp cron))
        (check "list-cron-jobs typed" (every #'cron-record-p cron)))

      (let ((health (adapter-system-health adapter)))
        (check "system-health returns list" (listp health))
        (check "system-health typed" (every #'health-record-p health)))

      (let ((usage (adapter-usage-records adapter :period :hourly)))
        (check "usage-records returns list" (listp usage))
        (check "usage-records typed" (every #'usage-record-p usage)))

      (let ((events (adapter-tail-events adapter :since 0 :limit 10)))
        (check "tail-events returns list" (listp events))
        (check "tail-events typed" (every #'event-record-p events))
        (check "tail-events limit" (<= (length events) 10)))

      (let ((alerts (adapter-list-alerts adapter)))
        (check "list-alerts returns list" (listp alerts))
        (check "list-alerts typed" (every #'alert-record-p alerts)))

      (let ((subs (adapter-list-subagents adapter)))
        (check "list-subagents returns list" (listp subs))
        (check "list-subagents typed" (every #'subagent-record-p subs)))

      (let ((caps (adapter-capabilities adapter)))
        (check "capabilities returns list" (listp caps))
        (check "capabilities typed" (every #'adapter-capability-p caps))
        (check "capabilities has trigger-cron"
               (find "trigger-cron" caps :key #'cap-name :test #'string=)))

      ;; optional command exercise on obvious IDs where possible
      (when exercise-commands
        (let ((cron (first (adapter-list-cron-jobs adapter)))
              (alert (first (adapter-list-alerts adapter))))
          (when cron
            (handler-case
                (progn
                  (adapter-trigger-cron adapter (cr-name cron))
                  (adapter-pause-cron adapter (cr-name cron))
                  (adapter-resume-cron adapter (cr-name cron)))
              (error (e)
                (push (format nil "command failure (cron): ~A" e) failures))))
          (when alert
            (handler-case
                (progn
                  (adapter-acknowledge-alert adapter (ar-id alert))
                  (adapter-snooze-alert adapter (ar-id alert) 60))
              (error (e)
                (push (format nil "command failure (alert): ~A" e) failures)))))))

    (values (null failures) (nreverse failures))))
