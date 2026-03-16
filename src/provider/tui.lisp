;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui.lisp — TUI data provider: typed queries for cl-term rendering
;;;
;;; Pure data transforms from sync-store into paginated, filtered, sorted
;;; view structures suitable for terminal UI rendering. No side effects.
;;; All functions accept a sync-store and return typed view structs.
;;;
;;; Architecture: sync-store → filter → sort → paginate → view-wrap
;;;
;;; Bead: agent-orrery-87i

(in-package #:orrery/provider)

;;; ============================================================
;;; Generic containers
;;; ============================================================

(defstruct (page (:conc-name page-))
  "Paginated result container. Items is a list of wrapped view structs."
  (items  '() :type list)
  (offset   0 :type fixnum)
  (limit   50 :type fixnum)
  (total    0 :type fixnum))

(defstruct (sort-spec (:conc-name sort-spec-))
  "Sort specification: which key accessor and direction."
  (key   #'identity :type function)
  (direction :ascending :type (member :ascending :descending)))

(defstruct (filter-spec (:conc-name filter-spec-))
  "Filter specification: field accessor, comparison op, and value."
  (field #'identity :type function)
  (op        :eq    :type (member :eq :neq :contains :gt :lt :gte :lte))
  (value     nil))

;;; ============================================================
;;; View types — display-ready wrappers around domain records
;;; ============================================================

(defstruct (session-view (:conc-name sv-))
  "Session record enriched with display-ready fields."
  (record          nil :type (or null session-record))
  (age-seconds       0 :type fixnum)
  (cost-display     "" :type string)
  (token-display    "" :type string))

(defstruct (cron-view (:conc-name cv-))
  "Cron record enriched with display-ready fields."
  (record           nil :type (or null cron-record))
  (overdue-p        nil :type boolean)
  (error-p          nil :type boolean)
  (interval-display  "" :type string))

(defstruct (health-view (:conc-name hv-))
  "Health record enriched with display-ready fields."
  (record       nil :type (or null health-record))
  (ok-p           t :type boolean)
  (latency-display "" :type string))

(defstruct (event-view (:conc-name ev-))
  "Event record enriched with display-ready fields."
  (record             nil :type (or null event-record))
  (age-seconds          0 :type fixnum)
  (severity-indicator  "" :type string))

(defstruct (alert-view (:conc-name alv-))
  "Alert record enriched with display-ready fields."
  (record       nil :type (or null alert-record))
  (active-p       t :type boolean)
  (age-seconds    0 :type fixnum)
  (urgency     :low :type keyword))

(defstruct (usage-view (:conc-name uv-))
  "Usage record enriched with display-ready fields."
  (record        nil :type (or null usage-record))
  (cost-display   "" :type string)
  (token-display  "" :type string))

(defstruct (dashboard-summary (:conc-name ds-))
  "Aggregate dashboard summary for TUI header/status bar."
  (session-count        0 :type fixnum)
  (active-session-count 0 :type fixnum)
  (cron-count           0 :type fixnum)
  (overdue-cron-count   0 :type fixnum)
  (health-ok-p          t :type boolean)
  (degraded-components '() :type list)
  (alert-count          0 :type fixnum)
  (critical-alert-count 0 :type fixnum)
  (total-tokens         0 :type fixnum)
  (total-cost-cents     0 :type fixnum)
  (last-sync-at         0 :type fixnum))

;;; ============================================================
;;; Display formatting helpers — pure string transforms
;;; ============================================================

(declaim (ftype (function (fixnum) string) format-tokens))
(defun format-tokens (n)
  "Format token count for TUI display. Uses K/M suffixes."
  (cond
    ((< n 1000) (format nil "~D" n))
    ((< n 1000000) (format nil "~,1FK" (/ n 1000.0)))
    (t (format nil "~,1FM" (/ n 1000000.0)))))

(declaim (ftype (function (fixnum) string) format-cost-cents))
(defun format-cost-cents (cents)
  "Format cost in cents as dollar string for TUI display."
  (if (< cents 100)
      (format nil "~D¢" cents)
      (format nil "$~,2F" (/ cents 100.0))))

(declaim (ftype (function (fixnum) string) format-age))
(defun format-age (seconds)
  "Format age in seconds as human-readable string."
  (cond
    ((< seconds 60) (format nil "~Ds" seconds))
    ((< seconds 3600) (format nil "~Dm" (floor seconds 60)))
    ((< seconds 86400) (format nil "~Dh" (floor seconds 3600)))
    (t (format nil "~Dd" (floor seconds 86400)))))

(declaim (ftype (function (fixnum) string) format-interval))
(defun format-interval (seconds)
  "Format interval duration as human-readable string."
  (cond
    ((< seconds 60) (format nil "~Ds" seconds))
    ((< seconds 3600) (format nil "~Dm~Ds" (floor seconds 60) (mod seconds 60)))
    (t (format nil "~Dh~Dm" (floor seconds 3600) (mod (floor seconds 60) 60)))))

;;; ============================================================
;;; Filtering engine — apply filter-spec list to a sequence
;;; ============================================================

(declaim (ftype (function (t (member :eq :neq :contains :gt :lt :gte :lte) t) boolean)
                apply-filter-op))
(defun apply-filter-op (field-value op test-value)
  "Apply a single filter comparison. Returns T if the item passes."
  (case op
    (:eq      (if (equal field-value test-value) t nil))
    (:neq     (if (equal field-value test-value) nil t))
    (:contains (if (and (stringp field-value) (stringp test-value)
                        (search test-value field-value :test #'char-equal))
                   t nil))
    (:gt      (if (and (numberp field-value) (numberp test-value) (> field-value test-value)) t nil))
    (:lt      (if (and (numberp field-value) (numberp test-value) (< field-value test-value)) t nil))
    (:gte     (if (and (numberp field-value) (numberp test-value) (>= field-value test-value)) t nil))
    (:lte     (if (and (numberp field-value) (numberp test-value) (<= field-value test-value)) t nil))
    (otherwise nil)))

(declaim (ftype (function (list list) list) apply-filters))
(defun apply-filters (items filters)
  "Apply all FILTERS (list of filter-spec) to ITEMS. Returns filtered list."
  (if (null filters)
      items
      (remove-if-not
       (lambda (item)
         (every (lambda (f)
                  (apply-filter-op
                   (funcall (filter-spec-field f) item)
                   (filter-spec-op f)
                   (filter-spec-value f)))
                filters))
       items)))

;;; ============================================================
;;; Sorting engine
;;; ============================================================

(declaim (ftype (function (list (or null sort-spec)) list) apply-sort))
(defun apply-sort (items sort)
  "Sort ITEMS by SORT-SPEC. Returns a fresh sorted list."
  (if (null sort)
      items
      (let ((key-fn (sort-spec-key sort))
            (desc-p (eq (sort-spec-direction sort) :descending)))
        (stable-sort
         (copy-list items)
         (lambda (a b)
           (let ((va (funcall key-fn a))
                 (vb (funcall key-fn b)))
             (cond
               ((and (numberp va) (numberp vb))
                (if desc-p (> va vb) (< va vb)))
               ((and (stringp va) (stringp vb))
                (if desc-p
                    (string> va vb)
                    (string< va vb)))
               ;; Keywords compared by symbol-name
               ((and (keywordp va) (keywordp vb))
                (if desc-p
                    (string> (symbol-name va) (symbol-name vb))
                    (string< (symbol-name va) (symbol-name vb))))
               (t nil))))))))

;;; ============================================================
;;; Pagination
;;; ============================================================

(declaim (ftype (function (list fixnum fixnum) page) paginate))
(defun paginate (items offset limit)
  "Return a PAGE from ITEMS starting at OFFSET with at most LIMIT items."
  (let* ((total (length items))
         (start (min offset total))
         (end (min (+ start limit) total)))
    (make-page
     :items (subseq items start end)
     :offset start
     :limit limit
     :total total)))

;;; ============================================================
;;; View constructors — wrap domain records with display data
;;; ============================================================

(declaim (ftype (function (session-record fixnum) session-view) wrap-session))
(defun wrap-session (rec now)
  "Wrap a session-record into a session-view with computed display fields."
  (let ((age (max 0 (- now (sr-updated-at rec)))))
    (make-session-view
     :record rec
     :age-seconds age
     :cost-display (format-cost-cents (sr-estimated-cost-cents rec))
     :token-display (format-tokens (sr-total-tokens rec)))))

(declaim (ftype (function (cron-record fixnum) cron-view) wrap-cron))
(defun wrap-cron (rec now)
  "Wrap a cron-record into a cron-view with computed display fields."
  (make-cron-view
   :record rec
   :overdue-p (and (eq (cr-status rec) :active)
                   (< (cr-next-run-at rec) now))
   :error-p (not (null (cr-last-error rec)))
   :interval-display (format-interval (cr-interval-s rec))))

(declaim (ftype (function (health-record) health-view) wrap-health))
(defun wrap-health (rec)
  "Wrap a health-record into a health-view."
  (make-health-view
   :record rec
   :ok-p (eq (hr-status rec) :ok)
   :latency-display (format nil "~Dms" (hr-latency-ms rec))))

(declaim (ftype (function (event-record fixnum) event-view) wrap-event))
(defun wrap-event (rec now)
  "Wrap an event-record into an event-view."
  (make-event-view
   :record rec
   :age-seconds (max 0 (- now (er-timestamp rec)))
   :severity-indicator (case (er-kind rec)
                         (:error "!!")
                         (:warning "! ")
                         (:info "  ")
                         (otherwise "? "))))

(declaim (ftype (function (alert-record fixnum) alert-view) wrap-alert))
(defun wrap-alert (rec now)
  "Wrap an alert-record into an alert-view."
  (let* ((snoozed-p (and (ar-snoozed-until rec)
                         (> (ar-snoozed-until rec) now)))
         (active-p (and (not (ar-acknowledged-p rec))
                        (not snoozed-p)))
         (age (max 0 (- now (ar-fired-at rec))))
         (urgency (if (not active-p)
                      :none
                      (case (ar-severity rec)
                        (:critical :critical)
                        (:error :high)
                        (:warning :medium)
                        (otherwise :low)))))
    (make-alert-view
     :record rec
     :active-p active-p
     :age-seconds age
     :urgency urgency)))

(declaim (ftype (function (usage-record) usage-view) wrap-usage))
(defun wrap-usage (rec)
  "Wrap a usage-record into a usage-view."
  (make-usage-view
   :record rec
   :cost-display (format-cost-cents (ur-estimated-cost-cents rec))
   :token-display (format-tokens (ur-total-tokens rec))))

;;; ============================================================
;;; Query functions — the public API
;;;
;;; Each takes a sync-store + optional filters/sort/pagination params
;;; and returns a page of view-wrapped records. All are pure functions
;;; (aside from GET-UNIVERSAL-TIME for age computation, overridable via NOW).
;;; ============================================================

(declaim (ftype (function (sync-store &key (:filters list) (:sort (or null sort-spec))
                                      (:offset fixnum) (:limit fixnum)
                                      (:now fixnum))
                          page)
                query-sessions))
(defun query-sessions (store &key (filters '()) (sort nil) (offset 0) (limit 50) (now (get-universal-time)))
  "Query sessions from STORE with filtering, sorting, pagination. Returns PAGE of session-view."
  (let* ((raw (ss-sessions store))
         (filtered (apply-filters raw filters))
         (sorted (apply-sort filtered (or sort (make-sort-spec :key #'sr-updated-at :direction :descending))))
         (paged (paginate sorted offset limit)))
    (make-page
     :items (mapcar (lambda (r) (wrap-session r now)) (page-items paged))
     :offset (page-offset paged)
     :limit (page-limit paged)
     :total (page-total paged))))

(declaim (ftype (function (sync-store &key (:filters list) (:sort (or null sort-spec))
                                      (:offset fixnum) (:limit fixnum)
                                      (:now fixnum))
                          page)
                query-cron-jobs))
(defun query-cron-jobs (store &key (filters '()) (sort nil) (offset 0) (limit 50) (now (get-universal-time)))
  "Query cron jobs from STORE. Returns PAGE of cron-view."
  (let* ((raw (ss-cron-jobs store))
         (filtered (apply-filters raw filters))
         (sorted (apply-sort filtered (or sort (make-sort-spec :key #'cr-next-run-at :direction :ascending))))
         (paged (paginate sorted offset limit)))
    (make-page
     :items (mapcar (lambda (r) (wrap-cron r now)) (page-items paged))
     :offset (page-offset paged)
     :limit (page-limit paged)
     :total (page-total paged))))

(declaim (ftype (function (sync-store &key (:filters list) (:sort (or null sort-spec)))
                          page)
                query-health))
(defun query-health (store &key (filters '()) (sort nil))
  "Query health records from STORE. Returns PAGE of health-view (no pagination, all shown)."
  (let* ((raw (ss-health store))
         (filtered (apply-filters raw filters))
         (sorted (apply-sort filtered (or sort (make-sort-spec :key #'hr-component :direction :ascending)))))
    (make-page
     :items (mapcar #'wrap-health sorted)
     :offset 0
     :limit (length sorted)
     :total (length sorted))))

(declaim (ftype (function (sync-store &key (:filters list) (:sort (or null sort-spec))
                                      (:offset fixnum) (:limit fixnum)
                                      (:now fixnum))
                          page)
                query-events))
(defun query-events (store &key (filters '()) (sort nil) (offset 0) (limit 100) (now (get-universal-time)))
  "Query events from STORE. Returns PAGE of event-view. Default sort: newest first."
  (let* ((raw (ss-events store))
         (filtered (apply-filters raw filters))
         (sorted (apply-sort filtered (or sort (make-sort-spec :key #'er-timestamp :direction :descending))))
         (paged (paginate sorted offset limit)))
    (make-page
     :items (mapcar (lambda (r) (wrap-event r now)) (page-items paged))
     :offset (page-offset paged)
     :limit (page-limit paged)
     :total (page-total paged))))

(declaim (ftype (function (sync-store &key (:filters list) (:sort (or null sort-spec))
                                      (:offset fixnum) (:limit fixnum)
                                      (:now fixnum))
                          page)
                query-alerts))
(defun query-alerts (store &key (filters '()) (sort nil) (offset 0) (limit 50) (now (get-universal-time)))
  "Query alerts from STORE. Returns PAGE of alert-view. Default sort: newest first."
  (let* ((raw (ss-alerts store))
         (filtered (apply-filters raw filters))
         (sorted (apply-sort filtered (or sort (make-sort-spec :key #'ar-fired-at :direction :descending))))
         (paged (paginate sorted offset limit)))
    (make-page
     :items (mapcar (lambda (r) (wrap-alert r now)) (page-items paged))
     :offset (page-offset paged)
     :limit (page-limit paged)
     :total (page-total paged))))

(declaim (ftype (function (sync-store &key (:filters list) (:sort (or null sort-spec)))
                          page)
                query-usage))
(defun query-usage (store &key (filters '()) (sort nil))
  "Query usage records from STORE. Returns PAGE of usage-view."
  (let* ((raw (ss-usage store))
         (filtered (apply-filters raw filters))
         (sorted (apply-sort filtered (or sort (make-sort-spec :key #'ur-total-tokens :direction :descending)))))
    (make-page
     :items (mapcar #'wrap-usage sorted)
     :offset 0
     :limit (length sorted)
     :total (length sorted))))

;;; ============================================================
;;; Dashboard summary — aggregate view for TUI header
;;; ============================================================

(declaim (ftype (function (sync-store &key (:now fixnum)) dashboard-summary)
                build-dashboard-summary)
         (ftype (function (dashboard-summary &key (:timestamp integer) (:sequence fixnum))
                          (values orrery/adapter:ui-message &optional))
                dashboard-summary-ui-message))
(defun build-dashboard-summary (store &key (now (get-universal-time)))
  "Build an aggregate dashboard summary from STORE. Pure function."
  (let* ((sessions (ss-sessions store))
         (crons (ss-cron-jobs store))
         (healths (ss-health store))
         (alerts (ss-alerts store))
         (usage-recs (ss-usage store))
         (active-sessions (count :active sessions :key #'sr-status))
         (overdue-crons (count-if (lambda (c)
                                    (and (eq (cr-status c) :active)
                                         (< (cr-next-run-at c) now)))
                                  crons))
         (degraded (remove-if (lambda (h) (eq (hr-status h) :ok)) healths))
         (active-alerts (remove-if (lambda (a)
                                     (or (ar-acknowledged-p a)
                                         (and (ar-snoozed-until a)
                                              (> (ar-snoozed-until a) now))))
                                   alerts))
         (critical-alerts (count :critical active-alerts :key #'ar-severity))
         (total-tok (reduce #'+ usage-recs :key #'ur-total-tokens :initial-value 0))
         (total-cost (reduce #'+ usage-recs :key #'ur-estimated-cost-cents :initial-value 0)))
    (make-dashboard-summary
     :session-count (length sessions)
     :active-session-count active-sessions
     :cron-count (length crons)
     :overdue-cron-count overdue-crons
     :health-ok-p (null degraded)
     :degraded-components (mapcar #'hr-component degraded)
     :alert-count (length active-alerts)
     :critical-alert-count critical-alerts
     :total-tokens total-tok
     :total-cost-cents total-cost
     :last-sync-at (ss-last-sync-at store))))

(defun dashboard-summary-ui-message (summary &key (timestamp 0) (sequence 0))
  "Project dashboard SUMMARY into typed UI message contract for TUI emitters."
  (declare (type dashboard-summary summary)
           (type integer timestamp)
           (type fixnum sequence)
           (optimize (safety 3)))
  (let* ((payload (list (cons :session_count (ds-session-count summary))
                        (cons :active_session_count (ds-active-session-count summary))
                        (cons :cron_count (ds-cron-count summary))
                        (cons :alert_count (ds-alert-count summary))
                        (cons :total_tokens (ds-total-tokens summary))
                        (cons :total_cost_cents (ds-total-cost-cents summary))))
         (message (orrery/adapter:make-ui-message* :tui :status timestamp sequence payload))
         (contract (orrery/adapter:make-ui-contract
                    :surface :tui
                    :kind :status
                    :required-fields '(:session_count :active_session_count :cron_count :alert_count :total_tokens :total_cost_cents)
                    :schema-version "1.0"))
         (errors (orrery/adapter:validate-ui-message message contract)))
    (when errors
      (error "TUI protocol contract violation: ~{~A~^, ~}" errors))
    message))
