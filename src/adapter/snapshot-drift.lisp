;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; snapshot-drift.lisp — Live snapshot drift diagnostic for gate evidence
;;;
;;; Bridges capture-driver snapshots and schema-drift detection to produce
;;; structured drift diagnostics consumable by the Epic 2 evidence pack.
;;; Pure functions, strict type declarations, modular design.
;;;
;;; Bead: agent-orrery-3nk

(in-package #:orrery/adapter)

;;; ─── Snapshot Schema Contract ───
;;;
;;; Defines the expected normalized shape for each capture endpoint,
;;; bridging capture-driver's endpoint vocabulary to schema-drift's
;;; protocol-schema contracts.

(defparameter *snapshot-endpoint-schemas*
  (list
   (make-protocol-schema
    :endpoint-name "/api/v1/health"
    :version "1.0"
    :fields (list (make-schema-field :name "status" :expected-type :string :required-p t)))
   (make-protocol-schema
    :endpoint-name "/api/v1/sessions"
    :version "1.0"
    :fields (list (make-schema-field :name "sessions" :expected-type :array :required-p t)))
   (make-protocol-schema
    :endpoint-name "/api/v1/cron"
    :version "1.0"
    :fields (list (make-schema-field :name "jobs" :expected-type :array :required-p t)))
   (make-protocol-schema
    :endpoint-name "/api/v1/events"
    :version "1.0"
    :fields (list (make-schema-field :name "events" :expected-type :array :required-p t)))
   (make-protocol-schema
    :endpoint-name "/api/v1/alerts"
    :version "1.0"
    :fields (list (make-schema-field :name "alerts" :expected-type :array :required-p t)))
   (make-protocol-schema
    :endpoint-name "/api/v1/usage"
    :version "1.0"
    :fields (list (make-schema-field :name "usage" :expected-type :object :required-p t))))
  "Normalized snapshot contract schemas for all standard capture endpoints.")

;;; ─── Snapshot Drift Diagnostic ───

(deftype diagnostic-disposition ()
  "Summary disposition for a snapshot drift analysis."
  '(member :clean :drift-detected :degraded :incompatible))

(defstruct (snapshot-drift-diagnostic
             (:constructor make-snapshot-drift-diagnostic
                 (&key snapshot-id profile endpoint-count
                       drift-reports breaking-count degrading-count
                       cosmetic-count info-count
                       disposition gate-evidence-ref timestamp))
             (:conc-name sdd-))
  "Complete drift diagnostic for one capture snapshot.
   Consumable by evidence-pack as gate evidence."
  (snapshot-id "" :type string)
  (profile :fixture :type capture-profile)
  (endpoint-count 0 :type (integer 0))
  (drift-reports '() :type list)       ; list of drift-report
  (breaking-count 0 :type (integer 0))
  (degrading-count 0 :type (integer 0))
  (cosmetic-count 0 :type (integer 0))
  (info-count 0 :type (integer 0))
  (disposition :clean :type diagnostic-disposition)
  (gate-evidence-ref "" :type string)
  (timestamp 0 :type integer))

;;; ─── Core Analysis ───

(declaim (ftype (function (capture-snapshot &key (:schemas list))
                          snapshot-drift-diagnostic)
                analyze-snapshot-drift))

(defun %count-findings-by-severity (reports severity)
  "Count findings across all drift reports matching SEVERITY."
  (declare (type list reports) (type drift-severity severity))
  (loop for r in reports
        sum (count severity (dr-findings r) :key #'df-severity)))

(defun %compute-disposition (breaking degrading)
  "Compute diagnostic disposition from severity counts."
  (declare (type (integer 0) breaking degrading))
  (cond
    ((plusp breaking) :incompatible)
    ((plusp degrading) :degraded)
    (t :clean)))

(defun analyze-snapshot-drift (snapshot &key (schemas *snapshot-endpoint-schemas*))
  "Analyze a capture snapshot against normalized schema contracts.
   Returns a snapshot-drift-diagnostic with per-endpoint drift reports.
   Pure function — no I/O."
  (declare (type capture-snapshot snapshot) (type list schemas)
           (optimize (safety 3)))
  (let* ((samples (cs-samples snapshot))
         ;; Build payload alist from capture samples: ((endpoint . body) ...)
         (payload-alist
           (loop for s in samples
                 unless (es-error-p s)
                   collect (cons (es-endpoint s) (es-body s))))
         ;; Run drift detection for each schema
         (reports (detect-all-drift schemas payload-alist))
         ;; Count severities
         (breaking (%count-findings-by-severity reports :breaking))
         (degrading (%count-findings-by-severity reports :degrading))
         (cosmetic (%count-findings-by-severity reports :cosmetic))
         (info-count (%count-findings-by-severity reports :info))
         (disposition (%compute-disposition breaking degrading)))
    (make-snapshot-drift-diagnostic
     :snapshot-id (cs-snapshot-id snapshot)
     :profile (ct-profile (cs-target snapshot))
     :endpoint-count (length reports)
     :drift-reports reports
     :breaking-count breaking
     :degrading-count degrading
     :cosmetic-count cosmetic
     :info-count info-count
     :disposition disposition
     :gate-evidence-ref (format nil "drift:~A:~A"
                                (cs-snapshot-id snapshot)
                                (string-downcase (symbol-name disposition)))
     :timestamp (get-universal-time))))

;;; ─── Comparative Analysis (Fixture vs Live) ───

(defstruct (drift-comparison
             (:constructor make-drift-comparison
                 (&key fixture-diagnostic live-diagnostic
                       regression-endpoints new-drifts resolved-drifts
                       compatible-p summary))
             (:conc-name dc-))
  "Comparison of drift diagnostics between fixture and live snapshots."
  (fixture-diagnostic (make-snapshot-drift-diagnostic) :type snapshot-drift-diagnostic)
  (live-diagnostic (make-snapshot-drift-diagnostic) :type snapshot-drift-diagnostic)
  (regression-endpoints '() :type list)   ; endpoints that regressed
  (new-drifts '() :type list)             ; drift-findings only in live
  (resolved-drifts '() :type list)        ; drift-findings only in fixture
  (compatible-p t :type boolean)
  (summary "" :type string))

(declaim (ftype (function (snapshot-drift-diagnostic snapshot-drift-diagnostic)
                          drift-comparison)
                compare-snapshot-drifts))

(defun %endpoint-drift-map (diagnostic)
  "Build alist of (endpoint-name . drift-report) from diagnostic."
  (declare (type snapshot-drift-diagnostic diagnostic))
  (loop for r in (sdd-drift-reports diagnostic)
        collect (cons (dr-endpoint-name r) r)))

(defun compare-snapshot-drifts (fixture-diag live-diag)
  "Compare drift diagnostics from fixture and live snapshots.
   Identifies regressions, new drifts, and resolved drifts.
   Pure function."
  (declare (type snapshot-drift-diagnostic fixture-diag live-diag)
           (optimize (safety 3)))
  (let* ((f-map (%endpoint-drift-map fixture-diag))
         (l-map (%endpoint-drift-map live-diag))
         (regressions '())
         (new-drifts '())
         (resolved '()))
    ;; Check each endpoint in live for regressions
    (dolist (lp l-map)
      (let* ((ep (car lp))
             (live-report (cdr lp))
             (fixture-report (cdr (assoc ep f-map :test #'string=))))
        (cond
          ;; Endpoint not in fixture — all findings are new
          ((null fixture-report)
           (dolist (f (dr-findings live-report))
             (push f new-drifts)))
          ;; Compare: live has breaking findings that fixture didn't
          ((and (not (dr-compatible-p live-report))
                (dr-compatible-p fixture-report))
           (push ep regressions)
           (dolist (f (dr-findings live-report))
             (unless (find (df-field-name f) (dr-findings fixture-report)
                           :key #'df-field-name :test #'string=)
               (push f new-drifts)))))))
    ;; Check for resolved drifts (in fixture but not in live)
    (dolist (fp f-map)
      (let* ((ep (car fp))
             (fixture-report (cdr fp))
             (live-report (cdr (assoc ep l-map :test #'string=))))
        (when (and live-report
                   (not (dr-compatible-p fixture-report))
                   (dr-compatible-p live-report))
          (dolist (f (dr-findings fixture-report))
            (unless (find (df-field-name f) (dr-findings live-report)
                          :key #'df-field-name :test #'string=)
              (push f resolved))))))
    (let ((compat (and (null regressions)
                       (eq (sdd-disposition live-diag) :clean))))
      (make-drift-comparison
       :fixture-diagnostic fixture-diag
       :live-diagnostic live-diag
       :regression-endpoints (nreverse regressions)
       :new-drifts (nreverse new-drifts)
       :resolved-drifts (nreverse resolved)
       :compatible-p compat
       :summary (format nil "~D endpoints checked; ~D regressions, ~
                             ~D new drifts, ~D resolved"
                        (sdd-endpoint-count live-diag)
                        (length regressions)
                        (length new-drifts)
                        (length resolved))))))

;;; ─── JSON Serialization (for gate evidence) ───

(declaim (ftype (function (snapshot-drift-diagnostic) string)
                snapshot-drift-diagnostic-to-json)
         (ftype (function (drift-comparison) string)
                drift-comparison-to-json))

(defun snapshot-drift-diagnostic-to-json (diag)
  "Serialize snapshot drift diagnostic to deterministic JSON for gate evidence."
  (declare (type snapshot-drift-diagnostic diag) (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"snapshot_id\":" s)
    (emit-json-string (sdd-snapshot-id diag) s)
    (write-string ",\"profile\":" s)
    (emit-json-string (string-downcase (symbol-name (sdd-profile diag))) s)
    (write-string ",\"endpoint_count\":" s)
    (write-string (princ-to-string (sdd-endpoint-count diag)) s)
    (write-string ",\"disposition\":" s)
    (emit-json-string (string-downcase (symbol-name (sdd-disposition diag))) s)
    (write-string ",\"breaking\":" s)
    (write-string (princ-to-string (sdd-breaking-count diag)) s)
    (write-string ",\"degrading\":" s)
    (write-string (princ-to-string (sdd-degrading-count diag)) s)
    (write-string ",\"cosmetic\":" s)
    (write-string (princ-to-string (sdd-cosmetic-count diag)) s)
    (write-string ",\"info\":" s)
    (write-string (princ-to-string (sdd-info-count diag)) s)
    (write-string ",\"gate_evidence_ref\":" s)
    (emit-json-string (sdd-gate-evidence-ref diag) s)
    (write-string ",\"drift_reports\":[" s)
    (let ((first t))
      (dolist (r (sdd-drift-reports diag))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string (drift-report-to-json r) s)))
    (write-string "]}" s)))

(defun drift-comparison-to-json (comp)
  "Serialize drift comparison to JSON for gate evidence."
  (declare (type drift-comparison comp) (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"compatible\":" s)
    (write-string (if (dc-compatible-p comp) "true" "false") s)
    (write-string ",\"summary\":" s)
    (emit-json-string (dc-summary comp) s)
    (write-string ",\"regression_endpoints\":[" s)
    (let ((first t))
      (dolist (ep (dc-regression-endpoints comp))
        (unless first (write-char #\, s))
        (setf first nil)
        (emit-json-string ep s)))
    (write-string "],\"new_drift_count\":" s)
    (write-string (princ-to-string (length (dc-new-drifts comp))) s)
    (write-string ",\"resolved_drift_count\":" s)
    (write-string (princ-to-string (length (dc-resolved-drifts comp))) s)
    (write-string ",\"fixture\":" s)
    (write-string (snapshot-drift-diagnostic-to-json
                   (dc-fixture-diagnostic comp)) s)
    (write-string ",\"live\":" s)
    (write-string (snapshot-drift-diagnostic-to-json
                   (dc-live-diagnostic comp)) s)
    (write-string "}" s)))
