;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-cron-ops-tests.lisp — Tests for TUI cron operations
;;; Bead: agent-orrery-eb0.3.3

(in-package #:orrery/harness-tests)

(define-test tui-cron-ops-suite

  ;; ─── Status transition validity ───

  (define-test cron-trigger-from-active-valid
    (is eq t (orrery/tui:cron-transition-valid-p :active :trigger)))

  (define-test cron-trigger-from-idle-valid
    (is eq t (orrery/tui:cron-transition-valid-p :idle :trigger)))

  (define-test cron-trigger-from-paused-invalid
    (is eq nil (orrery/tui:cron-transition-valid-p :paused :trigger)))

  (define-test cron-trigger-from-error-invalid
    (is eq nil (orrery/tui:cron-transition-valid-p :error :trigger)))

  (define-test cron-pause-from-active-valid
    (is eq t (orrery/tui:cron-transition-valid-p :active :pause)))

  (define-test cron-pause-from-idle-invalid
    (is eq nil (orrery/tui:cron-transition-valid-p :idle :pause)))

  (define-test cron-resume-from-paused-valid
    (is eq t (orrery/tui:cron-transition-valid-p :paused :resume)))

  (define-test cron-resume-from-idle-valid
    (is eq t (orrery/tui:cron-transition-valid-p :idle :resume)))

  (define-test cron-resume-from-active-invalid
    (is eq nil (orrery/tui:cron-transition-valid-p :active :resume)))

  (define-test cron-reset-from-error-valid
    (is eq t (orrery/tui:cron-transition-valid-p :error :reset)))

  (define-test cron-reset-from-active-invalid
    (is eq nil (orrery/tui:cron-transition-valid-p :active :reset)))

  ;; ─── Next status ───

  (define-test cron-next-status-trigger
    (is eq :running (orrery/tui:cron-next-status :active :trigger)))

  (define-test cron-next-status-pause
    (is eq :paused (orrery/tui:cron-next-status :active :pause)))

  (define-test cron-next-status-resume
    (is eq :active (orrery/tui:cron-next-status :paused :resume)))

  (define-test cron-next-status-reset
    (is eq :active (orrery/tui:cron-next-status :error :reset)))

  (define-test cron-next-status-invalid-stays
    (is eq :paused (orrery/tui:cron-next-status :paused :trigger)))

  ;; ─── Apply action ───

  (define-test apply-trigger-success
    (let* ((rec (orrery/domain:make-cron-record :name "watchdog" :status :active))
           (result (orrery/tui:apply-cron-action rec :trigger)))
      (is eq t (orrery/tui:cor-success-p result))
      (is eq :active (orrery/tui:cor-old-status result))
      (is eq :running (orrery/tui:cor-new-status result))
      (is string= "watchdog" (orrery/tui:cor-job-name result))))

  (define-test apply-trigger-denied
    (let* ((rec (orrery/domain:make-cron-record :name "sync" :status :paused))
           (result (orrery/tui:apply-cron-action rec :trigger)))
      (is eq nil (orrery/tui:cor-success-p result))
      (is eq :paused (orrery/tui:cor-old-status result))
      (is eq :paused (orrery/tui:cor-new-status result))))

  ;; ─── Record with new status ───

  (define-test record-with-new-status-trigger
    (let* ((rec (orrery/domain:make-cron-record :name "w" :status :active :run-count 5))
           (new (orrery/tui:cron-record-with-new-status rec :trigger)))
      (is eq :running (orrery/domain:cr-status new))
      (is = 6 (orrery/domain:cr-run-count new))))

  (define-test record-with-new-status-reset-clears-error
    (let* ((rec (orrery/domain:make-cron-record :name "w" :status :error
                                                :last-error "timeout"))
           (new (orrery/tui:cron-record-with-new-status rec :reset)))
      (is eq :active (orrery/domain:cr-status new))
      (is eq nil (orrery/domain:cr-last-error new))))

  ;; ─── Cron ops state ───

  (define-test cos-move-selection-clamp
    (let* ((jobs (list (orrery/domain:make-cron-record :name "a")
                       (orrery/domain:make-cron-record :name "b")))
           (state (orrery/tui:make-cron-ops-state :jobs jobs :selected-index 0))
           (moved (orrery/tui:cos-move-selection state 5)))
      (is = 1 (orrery/tui:cos-selected-index moved))))

  (define-test cos-move-selection-clamp-negative
    (let* ((jobs (list (orrery/domain:make-cron-record :name "a")))
           (state (orrery/tui:make-cron-ops-state :jobs jobs :selected-index 0))
           (moved (orrery/tui:cos-move-selection state -5)))
      (is = 0 (orrery/tui:cos-selected-index moved))))

  (define-test cos-confirm-action-applies
    (let* ((jobs (list (orrery/domain:make-cron-record :name "w" :status :active)))
           (state (orrery/tui:make-cron-ops-state :jobs jobs :selected-index 0))
           (pending (orrery/tui:cos-request-action state :trigger))
           (confirmed (orrery/tui:cos-confirm-action pending)))
      (is eq nil (orrery/tui:cos-confirm-pending confirmed))
      (true (orrery/tui:cos-last-result confirmed))
      (is eq t (orrery/tui:cor-success-p (orrery/tui:cos-last-result confirmed)))
      (is eq :running (orrery/domain:cr-status (first (orrery/tui:cos-jobs confirmed))))))

  (define-test cos-cancel-action-clears
    (let* ((state (orrery/tui:make-cron-ops-state :confirm-pending :pause))
           (cancelled (orrery/tui:cos-cancel-action state)))
      (is eq nil (orrery/tui:cos-confirm-pending cancelled))))

  ;; ─── Render ───

  (define-test cron-status-display-active
    (is string= "[ACTIVE]" (orrery/tui:cron-status-display :active)))

  (define-test cron-status-display-paused
    (is string= "[PAUSED]" (orrery/tui:cron-status-display :paused)))

  (define-test cron-status-display-error
    (is string= "[ERROR]" (orrery/tui:cron-status-display :error)))

  (define-test render-cron-ops-lines-non-empty
    (let* ((jobs (list (orrery/domain:make-cron-record :name "w" :status :active)))
           (state (orrery/tui:make-cron-ops-state :jobs jobs :selected-index 0))
           (lines (orrery/tui:render-cron-ops-lines state)))
      (true (> (length lines) 0))
      (true (search "ACTIVE" (first lines)))))

  ;; ─── Available actions ───

  (define-test available-actions-active
    (let ((actions (orrery/tui:available-cron-actions :active)))
      (true (member :trigger actions))
      (true (member :pause actions))
      (is eq nil (member :resume actions))
      (is eq nil (member :reset actions))))

  (define-test available-actions-paused
    (let ((actions (orrery/tui:available-cron-actions :paused)))
      (true (member :resume actions))
      (true (member :reset actions))
      (is eq nil (member :trigger actions))
      (is eq nil (member :pause actions))))

  (define-test available-actions-error
    (let ((actions (orrery/tui:available-cron-actions :error)))
      (true (member :reset actions))
      (is eq nil (member :trigger actions)))))
