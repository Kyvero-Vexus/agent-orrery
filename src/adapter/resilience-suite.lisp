;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; resilience-suite.lisp — Typed adapter fault/recovery resilience suite
;;;
;;; Bead: agent-orrery-eb0.7.2

(in-package #:orrery/adapter)

(deftype fault-class ()
  '(member :timeout :crash :partial-data :empty-response :malformed
           :not-supported :not-found :intermittent))

(deftype recovery-action ()
  '(member :retry :fallback :degrade :abort :skip))

(defstruct (fault-scenario (:conc-name fs-))
  "One injected fault scenario for resilience testing."
  (scenario-id "" :type string)
  (fault-class :timeout :type fault-class)
  (target-operation :sessions :type keyword)
  (description "" :type string)
  (inject-fn (constantly nil) :type function)
  (expected-recovery :degrade :type recovery-action)
  (expected-condition-type nil :type (or null symbol)))

(defstruct (resilience-result (:conc-name rr-))
  "Result of one resilience scenario."
  (scenario-id "" :type string)
  (pass-p nil :type boolean)
  (fault-class :timeout :type fault-class)
  (actual-recovery :abort :type recovery-action)
  (expected-recovery :degrade :type recovery-action)
  (condition-caught-p nil :type boolean)
  (condition-type-match-p nil :type boolean)
  (elapsed-ms 0 :type fixnum)
  (detail "" :type string))

(defstruct (resilience-report (:conc-name rrep-))
  "Complete resilience suite report."
  (pass-p nil :type boolean)
  (total 0 :type fixnum)
  (passed 0 :type fixnum)
  (failed 0 :type fixnum)
  (results nil :type list)
  (timestamp 0 :type integer))

(declaim
 (ftype (function () (values list &optional)) make-default-resilience-scenarios)
 (ftype (function (fault-scenario) (values resilience-result &optional)) run-resilience-scenario)
 (ftype (function (list &key (:timestamp integer)) (values resilience-report &optional)) run-resilience-suite)
 (ftype (function (resilience-result) (values string &optional)) resilience-result->json)
 (ftype (function (resilience-report) (values string &optional)) resilience-report->json))

;;; ─── Fault injection adapters ───

(defclass fault-injecting-adapter ()
  ((delegate :initarg :delegate :reader fia-delegate)
   (fault-fn :initarg :fault-fn :reader fia-fault-fn :type function)
   (target-op :initarg :target-op :reader fia-target-op :type keyword))
  (:documentation "Wraps a real adapter and injects faults for target operations."))

(defun make-fault-injecting-adapter (delegate target-op fault-fn)
  (make-instance 'fault-injecting-adapter
                 :delegate delegate
                 :target-op target-op
                 :fault-fn fault-fn))

(defmacro %delegate-or-fault (adapter op-keyword body)
  `(if (eq (fia-target-op ,adapter) ,op-keyword)
       (funcall (fia-fault-fn ,adapter))
       ,body))

(defmethod adapter-list-sessions ((a fault-injecting-adapter))
  (%delegate-or-fault a :sessions (adapter-list-sessions (fia-delegate a))))

(defmethod adapter-session-history ((a fault-injecting-adapter) sid)
  (%delegate-or-fault a :history (adapter-session-history (fia-delegate a) sid)))

(defmethod adapter-list-cron-jobs ((a fault-injecting-adapter))
  (%delegate-or-fault a :cron (adapter-list-cron-jobs (fia-delegate a))))

(defmethod adapter-system-health ((a fault-injecting-adapter))
  (%delegate-or-fault a :health (adapter-system-health (fia-delegate a))))

(defmethod adapter-usage-records ((a fault-injecting-adapter) &key (period :hourly))
  (%delegate-or-fault a :usage (adapter-usage-records (fia-delegate a) :period period)))

(defmethod adapter-tail-events ((a fault-injecting-adapter) &key (since 0) (limit 50))
  (%delegate-or-fault a :events (adapter-tail-events (fia-delegate a) :since since :limit limit)))

(defmethod adapter-list-alerts ((a fault-injecting-adapter))
  (%delegate-or-fault a :alerts (adapter-list-alerts (fia-delegate a))))

(defmethod adapter-list-subagents ((a fault-injecting-adapter))
  (%delegate-or-fault a :subagents (adapter-list-subagents (fia-delegate a))))

(defmethod adapter-trigger-cron ((a fault-injecting-adapter) job)
  (%delegate-or-fault a :trigger-cron (adapter-trigger-cron (fia-delegate a) job)))

(defmethod adapter-pause-cron ((a fault-injecting-adapter) job)
  (%delegate-or-fault a :pause-cron (adapter-pause-cron (fia-delegate a) job)))

(defmethod adapter-resume-cron ((a fault-injecting-adapter) job)
  (%delegate-or-fault a :resume-cron (adapter-resume-cron (fia-delegate a) job)))

(defmethod adapter-acknowledge-alert ((a fault-injecting-adapter) id)
  (%delegate-or-fault a :ack-alert (adapter-acknowledge-alert (fia-delegate a) id)))

(defmethod adapter-snooze-alert ((a fault-injecting-adapter) id dur)
  (%delegate-or-fault a :snooze-alert (adapter-snooze-alert (fia-delegate a) id dur)))

(defmethod adapter-capabilities ((a fault-injecting-adapter))
  (adapter-capabilities (fia-delegate a)))

;;; ─── Recovery logic ───

(defun attempt-with-recovery (adapter operation-key thunk)
  "Attempt THUNK, classify recovery action on failure."
  (declare (type keyword operation-key) (type function thunk) (optimize (safety 3)))
  (let ((start (get-internal-real-time))
        (result nil)
        (recovery :abort)
        (condition-caught nil)
        (cond-type nil))
    (handler-case
        (progn
          (setf result (funcall thunk))
          (setf recovery (if result :retry :skip)))
      (adapter-not-supported (c)
        (declare (ignore c))
        (setf condition-caught t cond-type 'adapter-not-supported recovery :skip))
      (adapter-not-found (c)
        (declare (ignore c))
        (setf condition-caught t cond-type 'adapter-not-found recovery :fallback))
      (error (c)
        (declare (ignore c))
        (setf condition-caught t cond-type 'error recovery :degrade)))
    (let ((elapsed (truncate (* 1000 (- (get-internal-real-time) start))
                             internal-time-units-per-second)))
      (values result recovery condition-caught cond-type elapsed))))

;;; ─── Stub adapter for standalone use ───

(defclass stub-adapter () ()
  (:documentation "Minimal adapter stub returning empty lists for all operations."))

(defun %make-stub-adapter () (make-instance 'stub-adapter))

(defmethod adapter-list-sessions ((a stub-adapter)) nil)
(defmethod adapter-session-history ((a stub-adapter) sid) (declare (ignore sid)) nil)
(defmethod adapter-list-cron-jobs ((a stub-adapter)) nil)
(defmethod adapter-system-health ((a stub-adapter)) nil)
(defmethod adapter-usage-records ((a stub-adapter) &key (period :hourly)) (declare (ignore period)) nil)
(defmethod adapter-tail-events ((a stub-adapter) &key (since 0) (limit 50)) (declare (ignore since limit)) nil)
(defmethod adapter-list-alerts ((a stub-adapter)) nil)
(defmethod adapter-list-subagents ((a stub-adapter)) nil)
(defmethod adapter-trigger-cron ((a stub-adapter) job) (declare (ignore job)) t)
(defmethod adapter-pause-cron ((a stub-adapter) job) (declare (ignore job)) t)
(defmethod adapter-resume-cron ((a stub-adapter) job) (declare (ignore job)) t)
(defmethod adapter-acknowledge-alert ((a stub-adapter) id) (declare (ignore id)) t)
(defmethod adapter-snooze-alert ((a stub-adapter) id dur) (declare (ignore id dur)) t)
(defmethod adapter-capabilities ((a stub-adapter)) nil)

;;; ─── Scenario execution ───

(defun run-resilience-scenario (scenario &key delegate)
  "Execute one fault-injection scenario and evaluate recovery.
DELEGATE is a pre-built adapter instance. If nil, a minimal stub is used."
  (declare (type fault-scenario scenario) (optimize (safety 3)))
  (let* ((delegate (or delegate (%make-stub-adapter)))
         (faulty (make-fault-injecting-adapter
                  delegate
                  (fs-target-operation scenario)
                  (fs-inject-fn scenario))))
    (multiple-value-bind (result recovery caught cond-type elapsed)
        (attempt-with-recovery
         faulty
         (fs-target-operation scenario)
         (lambda ()
           (ecase (fs-target-operation scenario)
             (:sessions (adapter-list-sessions faulty))
             (:health (adapter-system-health faulty))
             (:cron (adapter-list-cron-jobs faulty))
             (:usage (adapter-usage-records faulty))
             (:events (adapter-tail-events faulty))
             (:alerts (adapter-list-alerts faulty))
             (:subagents (adapter-list-subagents faulty))
             (:trigger-cron (adapter-trigger-cron faulty "cron-001"))
             (:not-found (adapter-trigger-cron faulty "nonexistent")))))
      (declare (ignore result))
      (let* ((expected (fs-expected-recovery scenario))
             (cond-match (if (fs-expected-condition-type scenario)
                             (eq cond-type (fs-expected-condition-type scenario))
                             (not caught)))
             (recovery-match (eq recovery expected))
             (pass (and recovery-match cond-match)))
        (make-resilience-result
         :scenario-id (fs-scenario-id scenario)
         :pass-p pass
         :fault-class (fs-fault-class scenario)
         :actual-recovery recovery
         :expected-recovery expected
         :condition-caught-p caught
         :condition-type-match-p cond-match
         :elapsed-ms elapsed
         :detail (format nil "recovery=~A(expected ~A) cond=~A(match=~A)"
                         recovery expected cond-type cond-match))))))

;;; ─── Default scenarios ───

(defun make-default-resilience-scenarios ()
  "Deterministic resilience corpus."
  (declare (optimize (safety 3)))
  (list
   ;; Timeout: sessions operation hangs (simulated via sleep-free error)
   (make-fault-scenario
    :scenario-id "R1-timeout-sessions"
    :fault-class :timeout
    :target-operation :sessions
    :description "Adapter sessions call raises timeout error"
    :inject-fn (lambda () (error "simulated timeout"))
    :expected-recovery :degrade
    :expected-condition-type 'error)

   ;; Crash: health check raises unexpected error
   (make-fault-scenario
    :scenario-id "R2-crash-health"
    :fault-class :crash
    :target-operation :health
    :description "Adapter health call crashes"
    :inject-fn (lambda () (error "simulated crash"))
    :expected-recovery :degrade
    :expected-condition-type 'error)

   ;; Empty response: events returns nil
   (make-fault-scenario
    :scenario-id "R3-empty-events"
    :fault-class :empty-response
    :target-operation :events
    :description "Adapter events returns nil"
    :inject-fn (lambda () nil)
    :expected-recovery :skip
    :expected-condition-type nil)

   ;; Partial data: usage returns truncated list
   (make-fault-scenario
    :scenario-id "R4-partial-usage"
    :fault-class :partial-data
    :target-operation :usage
    :description "Adapter usage returns single record"
    :inject-fn (lambda ()
                 (list (orrery/domain:make-usage-record
                        :model "gpt-4" :period :hourly :timestamp 1
                        :prompt-tokens 10 :completion-tokens 5
                        :total-tokens 15 :estimated-cost-cents 1)))
    :expected-recovery :retry
    :expected-condition-type nil)

   ;; Not-found: trigger nonexistent cron job
   (make-fault-scenario
    :scenario-id "R5-not-found-cron"
    :fault-class :not-found
    :target-operation :not-found
    :description "Trigger nonexistent cron job"
    :inject-fn (lambda () (error 'adapter-not-found :adapter nil :operation :cron :id "nonexistent"))
    :expected-recovery :fallback
    :expected-condition-type 'adapter-not-found)

   ;; Not-supported: adapter signals not-supported
   (make-fault-scenario
    :scenario-id "R6-not-supported-alerts"
    :fault-class :not-supported
    :target-operation :alerts
    :description "Adapter alerts not supported"
    :inject-fn (lambda () (error 'adapter-not-supported :adapter nil :operation :alerts))
    :expected-recovery :skip
    :expected-condition-type 'adapter-not-supported)

   ;; Malformed: cron returns non-list
   (make-fault-scenario
    :scenario-id "R7-malformed-cron"
    :fault-class :malformed
    :target-operation :cron
    :description "Adapter cron returns malformed data (string instead of list)"
    :inject-fn (lambda () "not-a-list")
    :expected-recovery :retry
    :expected-condition-type nil)))

;;; ─── Suite runner ───

(defun run-resilience-suite (scenarios &key (timestamp 0) delegate)
  "Run all resilience scenarios and build report."
  (declare (type list scenarios) (type integer timestamp) (optimize (safety 3)))
  (let ((results nil)
        (passed 0)
        (failed 0))
    (dolist (s scenarios)
      (let ((r (run-resilience-scenario s :delegate delegate)))
        (push r results)
        (if (rr-pass-p r) (incf passed) (incf failed))))
    (make-resilience-report
     :pass-p (zerop failed)
     :total (+ passed failed)
     :passed passed
     :failed failed
     :results (nreverse results)
     :timestamp timestamp)))

;;; ─── JSON emitters ───

(defun resilience-result->json (result)
  (declare (type resilience-result result) (optimize (safety 3)))
  (format nil "{\"id\":\"~A\",\"pass\":~A,\"fault\":\"~A\",\"actual_recovery\":\"~A\",\"expected_recovery\":\"~A\",\"condition_caught\":~A,\"elapsed_ms\":~D}"
          (rr-scenario-id result)
          (if (rr-pass-p result) "true" "false")
          (string-downcase (symbol-name (rr-fault-class result)))
          (string-downcase (symbol-name (rr-actual-recovery result)))
          (string-downcase (symbol-name (rr-expected-recovery result)))
          (if (rr-condition-caught-p result) "true" "false")
          (rr-elapsed-ms result)))

(defun resilience-report->json (report)
  (declare (type resilience-report report) (optimize (safety 3)))
  (format nil "{\"pass\":~A,\"total\":~D,\"passed\":~D,\"failed\":~D,\"timestamp\":~D,\"results\":[~{~A~^,~}]}"
          (if (rrep-pass-p report) "true" "false")
          (rrep-total report) (rrep-passed report) (rrep-failed report)
          (rrep-timestamp report)
          (mapcar #'resilience-result->json (rrep-results report))))
