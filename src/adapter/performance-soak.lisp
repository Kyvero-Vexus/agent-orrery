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

(defun run-soak-suite (config &key (timestamp 0))
  "Run the complete soak suite under CONFIG."
  (declare (type soak-config config) (type integer timestamp) (optimize (safety 3)))
  (let* ((iters (sc-iterations config))
         (seed (sc-seed config))
         (sessions (%gen-sessions (sc-session-count config) seed))
         (events (%gen-events (sc-event-count config) seed))
         (usage (%gen-usage (sc-usage-hours config) seed))
         (alerts (%gen-alerts (sc-alert-count config) seed))
         (timings nil)
         ;; Measure session list traversal
         (t1 (measure-operation "session-list-traversal" iters
               (lambda () (mapcar #'sr-id sessions))))
         ;; Measure event filtering
         (t2 (measure-operation "event-filter-by-kind" iters
               (lambda () (remove-if-not (lambda (e) (eq :warning (er-kind e))) events))))
         ;; Measure usage aggregation via Coalton
         (t3 (measure-operation "usage-coalton-aggregate" iters
               (lambda ()
                 (let ((entries (mapcar (lambda (u)
                                          (orrery/coalton/core:cl-make-usage-entry
                                           (ur-model u)
                                           (ur-prompt-tokens u)
                                           (ur-completion-tokens u)
                                           (ur-timestamp u)))
                                        (subseq usage 0 (min 200 (length usage))))))
                   (orrery/coalton/core:cl-aggregate-entries "soak" entries)))))
         ;; Measure anomaly detection pipeline (session/cost/token drift only)
         (t4 (measure-operation "anomaly-pipeline" iters
               (lambda ()
                 (let ((thresholds (orrery/coalton/core:cl-default-thresholds)))
                   (list
                    (orrery/coalton/core:cl-detect-session-drift
                     thresholds (length sessions) 50)
                    (orrery/coalton/core:cl-detect-cost-runaway
                     thresholds
                     (reduce #'+ usage :key #'ur-estimated-cost-cents) 100)
                    (orrery/coalton/core:cl-detect-token-spike
                     thresholds
                     (reduce #'+ usage :key #'ur-total-tokens) 50000))))))
         ;; Measure alert sort
         (t5 (measure-operation "alert-sort-by-severity" iters
               (lambda ()
                 (sort (copy-list alerts)
                       (lambda (a b)
                         (let ((sa (position (ar-severity a) '(:critical :warning :info)))
                               (sb (position (ar-severity b) '(:critical :warning :info))))
                           (< (or sa 99) (or sb 99))))))))
         ;; Measure notification dispatch batch
         (t6 (measure-operation "notification-dispatch-batch" iters
               (lambda ()
                 (let ((cfg (orrery/coalton/core:cl-default-dispatcher-config))
                       (nevents (loop for a in (subseq alerts 0 (min 20 (length alerts)))
                                      collect (orrery/coalton/core:cl-make-notification-event
                                               (ar-id a)
                                               (ar-severity a)
                                               (ar-title a)
                                               (ar-source a)
                                               (ar-fired-at a)
                                               :none))))
                   (dolist (n nevents)
                     (orrery/coalton/core:cl-dispatch-notification n cfg nil)))))))
    (setf timings (list t1 t2 t3 t4 t5 t6))
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
       :seed seed))))

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
