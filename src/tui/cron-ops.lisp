;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cron-ops.lisp — TUI cron operations: trigger, pause, resume, status transitions
;;; Bead: agent-orrery-eb0.3.3
;;;
;;; Pure functional core: all operations return new cron-record values.
;;; No side effects. Shell layer applies mutations.

(in-package #:orrery/tui)

;;; ─── Cron Status Transitions ───

(declaim (ftype (function (keyword keyword) (values boolean &optional))
                cron-transition-valid-p))
(defun cron-transition-valid-p (current-status action)
  "Check if a cron status transition is valid. Pure."
  (not (null (case action
               (:trigger  (member current-status '(:active :idle)))
               (:pause    (member current-status '(:active)))
               (:resume   (member current-status '(:paused :idle)))
               (:reset    (member current-status '(:error :paused :idle)))
               (otherwise nil)))))

(declaim (ftype (function (keyword keyword) (values keyword &optional))
                cron-next-status))
(defun cron-next-status (current-status action)
  "Compute the next status after a valid action. Pure.
   Returns the new status keyword, or current-status if transition is invalid."
  (if (cron-transition-valid-p current-status action)
      (case action
        (:trigger  :running)
        (:pause    :paused)
        (:resume   :active)
        (:reset    :active)
        (otherwise current-status))
      current-status))

;;; ─── Cron Operation Results ───

(defstruct (cron-op-result (:conc-name cor-))
  "Result of a cron operation attempt."
  (success-p nil :type boolean)
  (action    :trigger :type keyword)
  (job-name  "" :type string)
  (old-status :active :type keyword)
  (new-status :active :type keyword)
  (message   "" :type string))

(declaim (ftype (function (cron-record keyword) (values cron-op-result &optional))
                apply-cron-action))
(defun apply-cron-action (record action)
  "Apply an action to a cron record, returning a cron-op-result. Pure.
   Does NOT mutate the record — returns the result describing the transition."
  (let* ((old-status (cr-status record))
         (valid (cron-transition-valid-p old-status action))
         (new-status (if valid (cron-next-status old-status action) old-status)))
    (make-cron-op-result
     :success-p valid
     :action action
     :job-name (cr-name record)
     :old-status old-status
     :new-status new-status
     :message (if valid
                  (format nil "~A: ~A → ~A" (cr-name record) old-status new-status)
                  (format nil "Cannot ~A ~A (status: ~A)" action (cr-name record) old-status)))))

(declaim (ftype (function (cron-record keyword) (values cron-record &optional))
                cron-record-with-new-status))
(defun cron-record-with-new-status (record action)
  "Return a new cron-record with the status updated per the action. Pure.
   If the transition is invalid, returns a copy with unchanged status."
  (let ((new-status (cron-next-status (cr-status record) action)))
    (make-cron-record
     :name (cr-name record)
     :kind (cr-kind record)
     :interval-s (cr-interval-s record)
     :status new-status
     :last-run-at (cr-last-run-at record)
     :next-run-at (cr-next-run-at record)
     :run-count (if (and (eq action :trigger)
                         (cron-transition-valid-p (cr-status record) action))
                    (1+ (cr-run-count record))
                    (cr-run-count record))
     :last-error (if (eq action :reset) nil (cr-last-error record))
     :description (cr-description record))))

;;; ─── Cron Operations Panel Data ───

(defstruct (cron-ops-state (:conc-name cos-))
  "State for the cron operations panel."
  (selected-index 0 :type fixnum)
  (jobs nil :type list)
  (last-result nil :type (or null cron-op-result))
  (confirm-pending nil :type (or null keyword)))

(declaim (ftype (function (cron-ops-state) (values (or null cron-record) &optional))
                cos-selected-job))
(defun cos-selected-job (state)
  "Get the currently selected cron job. Pure."
  (nth (cos-selected-index state) (cos-jobs state)))

(declaim (ftype (function (cron-ops-state fixnum) (values cron-ops-state &optional))
                cos-move-selection))
(defun cos-move-selection (state delta)
  "Move selection by delta, clamping to valid range. Pure."
  (let* ((jobs (cos-jobs state))
         (max-idx (max 0 (1- (length jobs))))
         (new-idx (min max-idx (max 0 (+ (cos-selected-index state) delta)))))
    (make-cron-ops-state
     :selected-index new-idx
     :jobs jobs
     :last-result (cos-last-result state)
     :confirm-pending (cos-confirm-pending state))))

(declaim (ftype (function (cron-ops-state keyword) (values cron-ops-state &optional))
                cos-request-action))
(defun cos-request-action (state action)
  "Set a pending action confirmation. Pure."
  (make-cron-ops-state
   :selected-index (cos-selected-index state)
   :jobs (cos-jobs state)
   :last-result (cos-last-result state)
   :confirm-pending action))

(declaim (ftype (function (cron-ops-state) (values cron-ops-state &optional))
                cos-cancel-action))
(defun cos-cancel-action (state)
  "Cancel a pending action. Pure."
  (make-cron-ops-state
   :selected-index (cos-selected-index state)
   :jobs (cos-jobs state)
   :last-result (cos-last-result state)
   :confirm-pending nil))

(declaim (ftype (function (cron-ops-state) (values cron-ops-state &optional))
                cos-confirm-action))
(defun cos-confirm-action (state)
  "Execute the pending action on the selected job. Pure.
   Returns a new state with updated job list and result."
  (let* ((action (cos-confirm-pending state))
         (job (cos-selected-job state)))
    (if (and action job)
        (let* ((result (apply-cron-action job action))
               (new-job (if (cor-success-p result)
                            (cron-record-with-new-status job action)
                            job))
               (new-jobs (substitute new-job job (cos-jobs state) :test #'eq)))
          (make-cron-ops-state
           :selected-index (cos-selected-index state)
           :jobs new-jobs
           :last-result result
           :confirm-pending nil))
        ;; No action or no job — just clear pending
        (cos-cancel-action state))))

;;; ─── Render Helpers ───

(declaim (ftype (function (keyword) (values string &optional))
                cron-status-display))
(defun cron-status-display (status)
  "Format cron status for display. Pure."
  (case status
    (:active  "[ACTIVE]")
    (:running "[RUNNING]")
    (:paused  "[PAUSED]")
    (:idle    "[IDLE]")
    (:error   "[ERROR]")
    (otherwise (format nil "[~A]" status))))

(declaim (ftype (function (cron-record fixnum boolean) (values string &optional))
                render-cron-job-line))
(defun render-cron-job-line (record index selected-p)
  "Render a single cron job line for the TUI. Pure."
  (format nil "~A ~2D. ~A ~A  every ~Ds  runs:~D~A"
          (if selected-p ">" " ")
          index
          (cron-status-display (cr-status record))
          (cr-name record)
          (cr-interval-s record)
          (cr-run-count record)
          (if (cr-last-error record)
              (format nil "  err: ~A" (cr-last-error record))
              "")))

(declaim (ftype (function (cron-ops-state) (values list &optional))
                render-cron-ops-lines))
(defun render-cron-ops-lines (state)
  "Render all cron operation lines. Pure. Returns list of strings."
  (let ((lines nil)
        (idx 0))
    (dolist (job (cos-jobs state))
      (push (render-cron-job-line job idx (= idx (cos-selected-index state))) lines)
      (incf idx))
    ;; Status line
    (when (cos-last-result state)
      (push "" lines)
      (push (cor-message (cos-last-result state)) lines))
    ;; Confirm prompt
    (when (cos-confirm-pending state)
      (push "" lines)
      (let ((job (cos-selected-job state)))
        (push (format nil "Confirm ~A on ~A? [y/n]"
                      (cos-confirm-pending state)
                      (if job (cr-name job) "?"))
              lines)))
    (nreverse lines)))

;;; ─── Available Actions for a State ───

(declaim (ftype (function (keyword) (values list &optional))
                available-cron-actions))
(defun available-cron-actions (status)
  "Return the list of valid actions for a given cron status. Pure."
  (remove-if-not (lambda (action) (cron-transition-valid-p status action))
                 '(:trigger :pause :resume :reset)))
