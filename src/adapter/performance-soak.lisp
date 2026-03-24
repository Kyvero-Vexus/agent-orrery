;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; performance-soak.lisp — Performance/soak test infrastructure
;;;
;;; Bead: agent-orrery-eb0.7.1
;;; Typed soak harness: generates high-volume fixture data, measures
;;; pipeline throughput, and reports deterministic timing profiles.

(in-package #:orrery/adapter)

(deftype soak-profile ()
  '(member :light :medium :heavy :stress))

(defstruct (soak-config (:conc-name sc-))
  "Soak test configuration."
  (profile :medium :type soak-profile)
  (session-count 100 :type fixnum)
  (event-count 1000 :type fixnum)
  (usage-hours 168 :type fixnum)
  (alert-count 50 :type fixnum)
  (iterations 3 :type fixnum)
  (seed 0 :type fixnum))

(defstruct (soak-timing (:conc-name st-))
  "Timing for one soak operation."
  (operation "" :type string)
  (iterations 0 :type fixnum)
  (total-ms 0 :type fixnum)
  (min-ms 0 :type fixnum)
  (max-ms 0 :type fixnum)
  (mean-ms 0 :type fixnum)
  (items-processed 0 :type fixnum)
  (throughput-per-sec 0 :type fixnum))

(defstruct (soak-report (:conc-name srep-))
  "Complete soak test report."
  (profile :medium :type soak-profile)
  (pass-p nil :type boolean)
  (timings nil :type list)
  (total-items 0 :type fixnum)
  (total-ms 0 :type fixnum)
  (peak-memory-kb 0 :type fixnum)
  (timestamp 0 :type integer)
  (seed 0 :type fixnum))

(declaim
 (ftype (function (soak-profile) (values soak-config &optional)) make-soak-profile-config)
 (ftype (function (string fixnum (function () t)) (values soak-timing &optional)) measure-operation)
 (ftype (function (soak-config &key (:timestamp integer)) (values soak-report &optional)) run-soak-suite)
 (ftype (function (soak-timing) (values string &optional)) soak-timing->json)
 (ftype (function (soak-report) (values string &optional)) soak-report->json))

(defun make-soak-profile-config (profile)
  "Create soak config for a named profile."
  (declare (type soak-profile profile) (optimize (safety 3)))
  (ecase profile
    (:light  (make-soak-config :profile :light  :session-count 10   :event-count 100    :usage-hours 24  :alert-count 5   :iterations 3))
    (:medium (make-soak-config :profile :medium :session-count 100  :event-count 1000   :usage-hours 168 :alert-count 50  :iterations 5))
    (:heavy  (make-soak-config :profile :heavy  :session-count 500  :event-count 5000   :usage-hours 720 :alert-count 200 :iterations 5))
    (:stress (make-soak-config :profile :stress :session-count 2000 :event-count 20000  :usage-hours 2160 :alert-count 500 :iterations 3))))

(defun %get-internal-ms ()
  (declare (optimize (safety 3)))
  (truncate (* 1000 (get-internal-real-time)) internal-time-units-per-second))

(defun measure-operation (name iterations thunk)
  "Run THUNK ITERATIONS times and return a soak-timing."
  (declare (type string name) (type fixnum iterations) (type function thunk) (optimize (safety 3)))
  (let ((times nil)
        (total-items 0))
    (dotimes (_ iterations)
      (let* ((start (%get-internal-ms))
             (result (funcall thunk))
             (end (%get-internal-ms))
             (elapsed (max 1 (- end start))))
        (push elapsed times)
        (when (listp result)
          (incf total-items (length result)))))
    (let* ((sorted (sort (copy-list times) #'<))
           (total (reduce #'+ sorted))
           (min-t (first sorted))
           (max-t (car (last sorted)))
           (mean-t (truncate total iterations))
           (throughput (if (zerop total) 0
                           (truncate (* total-items 1000) total))))
      (make-soak-timing
       :operation name
       :iterations iterations
       :total-ms total
       :min-ms min-t
       :max-ms max-t
       :mean-ms mean-t
       :items-processed total-items
       :throughput-per-sec throughput))))

(defun %gen-sessions (count seed)
  (declare (type fixnum count seed) (optimize (safety 3)))
  (loop for i from 1 to count
        collect (orrery/domain:make-session-record
                 :id (format nil "soak-sess-~D-~D" seed i)
                 :agent-name (format nil "agent-~D" (mod i 10))
                 :channel (nth (mod i 5) '("telegram" "irc" "webchat" "discord" "slack"))
                 :status (nth (mod i 4) '(:active :active :idle :closed))
                 :model (nth (mod i 3) '("gpt-4" "claude-3" "llama-70b"))
                 :created-at (* i 100)
                 :updated-at (* i 200)
                 :message-count (* i 5)
                 :total-tokens (* i 500)
                 :estimated-cost-cents (1+ i))))

(defun %gen-events (count seed)
  (declare (type fixnum count seed) (optimize (safety 3)))
  (loop for i from 1 to count
        collect (orrery/domain:make-event-record
                 :id (format nil "soak-ev-~D-~D" seed i)
                 :kind (nth (mod i 5) '(:info :info :warning :error :action))
                 :source (format nil "source-~D" (mod i 8))
                 :message (format nil "Event ~D from soak seed ~D" i seed)
                 :timestamp (+ (* seed 100000) i)
                 :metadata nil)))

(defun %gen-usage (hours seed)
  (declare (type fixnum hours seed) (optimize (safety 3)))
  (loop for h from 0 below hours
        for base = (* (+ 100 seed) (1+ (mod h 7)))
        collect (orrery/domain:make-usage-record
                 :model (nth (mod h 3) '("gpt-4" "claude-3" "llama-70b"))
                 :period :hourly
                 :timestamp (+ (* seed 100000) (* h 3600))
                 :prompt-tokens (truncate (* base 6) 10)
                 :completion-tokens (- base (truncate (* base 6) 10))
                 :total-tokens base
                 :estimated-cost-cents (max 1 (truncate base 500)))))

(defun %gen-alerts (count seed)
  (declare (type fixnum count seed) (optimize (safety 3)))
  (loop for i from 1 to count
        collect (orrery/domain:make-alert-record
                 :id (format nil "soak-alert-~D-~D" seed i)
                 :severity (nth (mod i 3) '(:info :warning :critical))
                 :title (format nil "Alert ~D" i)
                 :message (format nil "Soak alert ~D seed ~D" i seed)
                 :source (format nil "soak-~D" (mod i 4))
                 :fired-at (+ (* seed 100000) (* i 10))
                 :acknowledged-p (evenp i)
                 :snoozed-until nil)))

(defun %soak-hash-fn (input)
  (declare (type string input) (optimize (safety 3)))
  (format nil "~64,'0X" (abs (sxhash input))))

(defun %mk-cost-profiles ()
  (declare (optimize (safety 3)))
  (list (orrery/coalton/core:cl-make-model-cost-profile "gpt-4" 30 60 95 40)
        (orrery/coalton/core:cl-make-model-cost-profile "claude-3" 22 44 90 45)
        (orrery/coalton/core:cl-make-model-cost-profile "llama-70b" 10 16 78 70)))

(defun %mk-cost-entries (usage)
  (declare (type list usage) (optimize (safety 3)))
  (mapcar (lambda (u)
            (orrery/coalton/core:cl-make-usage-entry
             (ur-model u)
             (ur-prompt-tokens u)
             (ur-completion-tokens u)
             (ur-timestamp u)))
          usage))

(defun %mk-session-metrics (sessions usage)
  (declare (type list sessions usage) (optimize (safety 3)))
  (loop for s in (subseq sessions 0 (min 120 (length sessions)))
        for idx from 0
        for u = (nth (mod idx (max 1 (length usage))) usage)
        collect (orrery/coalton/core:cl-make-session-metric
                 (sr-id s)
                 (+ 30 (* 5 (mod idx 90)))
                 (ur-total-tokens u)
                 (max 1 (truncate (ur-total-tokens u) 120))
                 (max 1 (ur-estimated-cost-cents u))
                 (orrery/domain:sr-model s))))

(defun run-soak-suite (config &key (timestamp 0))
  "Run the complete soak suite under CONFIG."
  (declare (type soak-config config) (type integer timestamp) (optimize (safety 3)))
  (let* ((iters (sc-iterations config))
         (seed (sc-seed config))
         (sessions (%gen-sessions (sc-session-count config) seed))
         (events (%gen-events (sc-event-count config) seed))
         (usage (%gen-usage (sc-usage-hours config) seed))
         (alerts (%gen-alerts (sc-alert-count config) seed))
         (profiles (%mk-cost-profiles))
         (cost-entries (%mk-cost-entries (subseq usage 0 (min 240 (length usage)))))
         (session-metrics (%mk-session-metrics sessions usage)))
    (let ((timings nil))
      (flet ((push-timing (name thunk)
               (push (measure-operation name iters thunk) timings)))
        ;; Core soak operations
        (push-timing "session-list-traversal"
                     (lambda () (mapcar #'sr-id sessions)))
        (push-timing "event-filter-by-kind"
                     (lambda () (remove-if-not (lambda (e) (eq :warning (er-kind e))) events)))
        (push-timing "usage-coalton-aggregate"
                     (lambda ()
                       (let ((entries (%mk-cost-entries (subseq usage 0 (min 200 (length usage))))))
                         (orrery/coalton/core:cl-aggregate-entries "soak" entries))))
        (push-timing "anomaly-pipeline"
                     (lambda ()
                       (let ((thresholds (orrery/coalton/core:cl-default-thresholds)))
                         (list
                          (orrery/coalton/core:cl-detect-session-drift thresholds (length sessions) 50)
                          (orrery/coalton/core:cl-detect-cost-runaway
                           thresholds (reduce #'+ usage :key #'ur-estimated-cost-cents) 100)
                          (orrery/coalton/core:cl-detect-token-spike
                           thresholds (reduce #'+ usage :key #'ur-total-tokens) 50000)))))
        (push-timing "alert-sort-by-severity"
                     (lambda ()
                       (sort (copy-list alerts)
                             (lambda (a b)
                               (let ((sa (position (ar-severity a) '(:critical :warning :info)))
                                     (sb (position (ar-severity b) '(:critical :warning :info))))
                                 (< (or sa 99) (or sb 99)))))))
        (push-timing "notification-dispatch-batch"
                     (lambda ()
                       (let ((cfg (orrery/coalton/core:cl-default-dispatcher-config))
                             (nevents (loop for a in (subseq alerts 0 (min 20 (length alerts)))
                                            collect (orrery/coalton/core:cl-make-notification-event
                                                     (ar-id a) (ar-severity a) (ar-title a)
                                                     (ar-source a) (ar-fired-at a) :none))))
                         (dolist (n nevents)
                           (orrery/coalton/core:cl-dispatch-notification n cfg nil)))))

        ;; v2 module soak operations
        (push-timing "audit-trail-append-verify"
                     (lambda ()
                       (let ((trail (orrery/coalton/core:cl-empty-trail)))
                         (dotimes (i 25 trail)
                           (setf trail (orrery/coalton/core:cl-append-entry
                                        #'%soak-hash-fn trail (+ 1000 i)
                                        (orrery/coalton/core:cl-audit-adapter-event)
                                        (orrery/coalton/core:cl-audit-info)
                                        "soak" "event" "append")))
                         (when (orrery/coalton/core:cl-verify-trail #'%soak-hash-fn trail)
                           (list (orrery/coalton/core:cl-trail-count trail))))))
        (push-timing "cost-optimizer-recommend"
                     (lambda ()
                       (let ((rec (orrery/coalton/core:cl-recommend-model
                                   profiles cost-entries
                                   (orrery/coalton/core:cl-opt-balanced))))
                         (list (orrery/coalton/core:cl-rr-model rec)
                               (orrery/coalton/core:cl-rr-confidence-label rec)))))
        (push-timing "capacity-planner-assess"
                     (lambda ()
                       (let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
                              (values (list (length sessions)
                                            (truncate (reduce #'+ usage :key #'ur-total-tokens)
                                                      (max 1 (sc-usage-hours config)))
                                            (truncate (reduce #'+ usage :key #'ur-estimated-cost-cents)
                                                      (max 1 (sc-usage-hours config)))
                                            (max 1 (truncate (length events)
                                                             (max 1 (sc-usage-hours config))))))
                              (plan (orrery/coalton/core:cl-build-capacity-plan thresholds values)))
                         (list (orrery/coalton/core:cl-plan-worst-zone-label plan)
                               (orrery/coalton/core:cl-plan-headroom-pct plan)))))
        (push-timing "session-analytics-summary"
                     (lambda ()
                       (let* ((summary (orrery/coalton/core:cl-analyze-sessions session-metrics))
                              (projection (coalton-analytics->projection summary)))
                         (list (orrery/coalton/core:cl-sas-total summary)
                               (sap-total-cost-cents projection))))))
      (setf timings (nreverse timings))
      (let* ((total-ms (reduce #'+ timings :key #'st-total-ms))
             (total-items (reduce #'+ timings :key #'st-items-processed))
             (mem-kb (truncate (sb-kernel:dynamic-usage) 1024)))
        (make-soak-report
         :profile (sc-profile config)
         :pass-p t
         :timings timings
         :total-items total-items
         :total-ms total-ms
         :peak-memory-kb mem-kb
         :timestamp timestamp
         :seed seed)))))

(defun soak-timing->json (timing)
  (declare (type soak-timing timing) (optimize (safety 3)))
  (format nil "{\"op\":\"~A\",\"iters\":~D,\"total_ms\":~D,\"min_ms\":~D,\"max_ms\":~D,\"mean_ms\":~D,\"items\":~D,\"throughput\":~D}"
          (st-operation timing) (st-iterations timing) (st-total-ms timing)
          (st-min-ms timing) (st-max-ms timing) (st-mean-ms timing)
          (st-items-processed timing) (st-throughput-per-sec timing)))

(defun soak-report->json (report)
  (declare (type soak-report report) (optimize (safety 3)))
  (format nil "{\"profile\":\"~A\",\"pass\":~A,\"total_items\":~D,\"total_ms\":~D,\"peak_memory_kb\":~D,\"seed\":~D,\"timings\":[~{~A~^,~}]}"
          (string-downcase (symbol-name (srep-profile report)))
          (if (srep-pass-p report) "true" "false")
          (srep-total-items report)
          (srep-total-ms report)
          (srep-peak-memory-kb report)
          (srep-seed report)
          (mapcar #'soak-timing->json (srep-timings report))))

;;; ---------------------------------------------------------------------------
;;; Concurrent Session Stress Test
;;; Spawns N threads, each simulating an independent session-list+filter
;;; operation, and collects results in a thread-safe manner.
;;; ---------------------------------------------------------------------------

(defstruct (concurrent-stress-result (:conc-name csr-))
  "Result of a concurrent session stress run."
  (thread-count 0 :type fixnum)
  (total-ops 0 :type fixnum)
  (success-count 0 :type fixnum)
  (error-count 0 :type fixnum)
  (elapsed-ms 0 :type fixnum)
  (ops-per-sec 0 :type fixnum)
  (pass-p nil :type boolean))

(declaim
 (ftype (function (fixnum &key (:seed fixnum)) (values concurrent-stress-result &optional))
        run-concurrent-session-stress))

(defun run-concurrent-session-stress (thread-count &key (seed 42))
  "Stress test with THREAD-COUNT concurrent threads each processing a session workload.
Each thread generates and filters a set of sessions/events deterministically.
Returns a CONCURRENT-STRESS-RESULT summarizing success rates and throughput."
  (declare (type fixnum thread-count seed) (optimize (safety 3)))
  (let* ((start-ms (%get-internal-ms))
         (results-lock (sb-thread:make-mutex :name "stress-results"))
         (success-counter 0)
         (error-counter 0)
         (ops-counter 0)
         (threads nil))
    ;; Spawn threads
    (dotimes (i thread-count)
      (let ((thread-seed (+ seed (* i 37))))
        (push
         (sb-thread:make-thread
          (lambda ()
            (handler-case
                (let* ((sessions (%gen-sessions 10 thread-seed))
                       (events (%gen-events 50 thread-seed))
                       (n-sess (length sessions))
                       (n-warn (length (remove-if-not
                                        (lambda (e) (eq :warning (er-kind e)))
                                        events))))
                  (declare (ignorable n-sess n-warn))
                  (sb-thread:with-mutex (results-lock)
                    (incf success-counter)
                    (incf ops-counter (+ n-sess n-warn))))
              (error ()
                (sb-thread:with-mutex (results-lock)
                  (incf error-counter)))))
          :name (format nil "stress-~D" i))
         threads)))
    ;; Join all threads
    (dolist (thr threads)
      (sb-thread:join-thread thr :default nil))
    (let* ((end-ms (%get-internal-ms))
           (elapsed (max 1 (- end-ms start-ms)))
           (ops-per-sec (truncate (* ops-counter 1000) elapsed))
           (pass-p (and (zerop error-counter)
                        (= success-counter thread-count))))
      (make-concurrent-stress-result
       :thread-count thread-count
       :total-ops ops-counter
       :success-count success-counter
       :error-count error-counter
       :elapsed-ms elapsed
       :ops-per-sec ops-per-sec
       :pass-p pass-p))))

(defun concurrent-stress-result->json (result)
  "Serialize CONCURRENT-STRESS-RESULT to JSON string."
  (declare (type concurrent-stress-result result) (optimize (safety 3)))
  (format nil "{\"thread_count\":~D,\"total_ops\":~D,\"success\":~D,\"errors\":~D,\"elapsed_ms\":~D,\"ops_per_sec\":~D,\"pass\":~A}"
          (csr-thread-count result)
          (csr-total-ops result)
          (csr-success-count result)
          (csr-error-count result)
          (csr-elapsed-ms result)
          (csr-ops-per-sec result)
          (if (csr-pass-p result) "true" "false")))
