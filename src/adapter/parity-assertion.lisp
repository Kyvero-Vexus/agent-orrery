;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; parity-assertion.lisp — Trace-aware parity assertion engine
;;;
;;; Defines assertion profiles per UI target (TUI/Web/McCLIM),
;;; runs trace-diff with customizable tolerance, produces
;;; structured pass/fail reports for CI gates.
;;;
;;; Builds on event-trace-canon (v4o).

(in-package #:orrery/adapter)

;;; ─── Types ───

(deftype ui-target ()
  '(member :tui :web :mcclim))

(defstruct (tolerance-spec (:conc-name tol-))
  "Tolerance thresholds for parity assertions."
  (max-mismatches 0 :type fixnum)
  (max-missing    0 :type fixnum)
  (required-kinds nil :type list))

(defstruct (assertion-profile (:conc-name ap-))
  "Configuration for parity checking against a specific UI target."
  (name             "" :type string)
  (target          :tui :type (member :tui :web :mcclim))
  (tolerance       (make-tolerance-spec) :type tolerance-spec)
  (required-sources nil :type list))

(deftype assertion-verdict ()
  '(member :pass :fail :skip))

(defstruct (assertion-entry (:conc-name ae-))
  "Single kind-level parity result."
  (kind-label   :session :type event-kind)
  (source-label :adapter :type source-tag)
  (expected-count 0 :type fixnum)
  (actual-count   0 :type fixnum)
  (verdict       :pass :type (member :pass :fail :skip))
  (detail        "" :type string))

(defstruct (parity-assertion-report (:conc-name par-))
  "Structured pass/fail report from a parity assertion run."
  (report-id       "" :type string)
  (profile-name    "" :type string)
  (target         :tui :type (member :tui :web :mcclim))
  (entries         nil :type list)
  (pass-count      0 :type fixnum)
  (fail-count      0 :type fixnum)
  (skip-count      0 :type fixnum)
  (overall-verdict :pass :type (member :pass :fail))
  (diff-summary    (make-trace-diff-result) :type trace-diff-result)
  (timestamp       0 :type fixnum))

;;; ─── Default Profiles ───

(declaim (ftype (function () (values tolerance-spec &optional))
                make-default-tolerance))
(defun make-default-tolerance ()
  "Zero-tolerance default. Pure."
  (declare (optimize (safety 3)))
  (make-tolerance-spec
   :max-mismatches 0
   :max-missing 0
   :required-kinds '(:session :cron :health :alert :usage :probe :lifecycle)))

(defvar *all-sources* '(:adapter :pipeline :store :harness)
  "All source tags.")

(defvar *all-kinds* '(:session :cron :health :alert :usage :probe :lifecycle)
  "All event kinds.")

(defvar *tui-parity-profile*
  (make-assertion-profile
   :name "tui-strict"
   :target :tui
   :tolerance (make-default-tolerance)
   :required-sources *all-sources*)
  "TUI: zero tolerance, all sources, all kinds required.")

(defvar *web-parity-profile*
  (make-assertion-profile
   :name "web-relaxed"
   :target :web
   :tolerance (make-tolerance-spec
               :max-mismatches 0
               :max-missing 1
               :required-kinds *all-kinds*)
   :required-sources *all-sources*)
  "Web: allows 1 missing (lifecycle may lag), all kinds required.")

(defvar *mcclim-parity-profile*
  (make-assertion-profile
   :name "mcclim-focused"
   :target :mcclim
   :tolerance (make-tolerance-spec
               :max-mismatches 0
               :max-missing 1
               :required-kinds '(:session :cron :health :alert))
   :required-sources *all-sources*)
  "McCLIM: allows 1 missing, requires session/cron/health/alert.")

;;; ─── Stream Filtering ───

(declaim (ftype (function (trace-stream list) (values trace-stream &optional))
                filter-stream-by-sources))
(defun filter-stream-by-sources (stream sources)
  "Filter trace-stream to only events from given sources. Pure."
  (declare (optimize (safety 3)))
  (let ((filtered (remove-if-not
                   (lambda (ev) (member (tev-source-tag ev) sources :test #'eq))
                   (ts-events stream))))
    (make-trace-stream :events filtered :count (length filtered))))

;;; ─── Counting ───

(declaim (ftype (function (trace-stream) (values list &optional))
                count-by-kind))
(defun count-by-kind (stream)
  "Return alist of (event-kind . count) for a trace-stream. Pure."
  (declare (optimize (safety 3)))
  (let ((counts nil))
    (dolist (ev (ts-events stream))
      (let ((pair (assoc (tev-event-kind ev) counts :test #'eq)))
        (if pair
            (incf (cdr pair))
            (push (cons (tev-event-kind ev) 1) counts))))
    (nreverse counts)))

;;; ─── Kind-level Evaluation ───

(declaim (ftype (function (event-kind fixnum fixnum tolerance-spec)
                          (values assertion-entry &optional))
                evaluate-kind-parity))
(defun evaluate-kind-parity (kind expected actual tolerance)
  "Evaluate parity for a single event kind. Pure."
  (declare (optimize (safety 3)))
  (let* ((required-p (member kind (tol-required-kinds tolerance) :test #'eq))
         (delta (abs (- expected actual)))
         (verdict (cond
                    ((= expected actual) :pass)
                    ((and (not required-p)
                          (<= delta (tol-max-missing tolerance)))
                     :skip)
                    ((and required-p (> delta 0))
                     :fail)
                    ((<= delta (tol-max-missing tolerance))
                     :pass)
                    (t :fail)))
         (detail (if (= expected actual)
                     "exact match"
                     (format nil "delta=~D required=~A" delta (if required-p "yes" "no")))))
    (make-assertion-entry
     :kind-label kind
     :source-label :adapter
     :expected-count expected
     :actual-count actual
     :verdict verdict
     :detail detail)))

;;; ─── Report ID ───

(declaim (ftype (function (string fixnum) (values string &optional))
                compute-report-id))
(defun compute-report-id (profile-name timestamp)
  "Deterministic report ID from profile name and timestamp. Pure."
  (declare (optimize (safety 3)))
  (format nil "par-~A-~D" profile-name timestamp))

;;; ─── Full Pipeline ───

(declaim (ftype (function (assertion-profile trace-stream trace-stream fixnum)
                          (values parity-assertion-report &optional))
                run-parity-assertion))
(defun run-parity-assertion (profile reference candidate timestamp)
  "Run full parity assertion: filter, diff, evaluate per-kind, produce report. Pure."
  (declare (optimize (safety 3)))
  (let* ((sources (ap-required-sources profile))
         (tolerance (ap-tolerance profile))
         (ref-filtered (filter-stream-by-sources reference sources))
         (cand-filtered (filter-stream-by-sources candidate sources))
         (diff (trace-diff ref-filtered cand-filtered))
         (ref-counts (count-by-kind ref-filtered))
         (cand-counts (count-by-kind cand-filtered))
         ;; Collect all kinds seen in either stream
         (all-seen-kinds (remove-duplicates
                          (append (mapcar #'car ref-counts)
                                  (mapcar #'car cand-counts))
                          :test #'eq))
         (entries
           (mapcar (lambda (kind)
                     (let ((ref-n (or (cdr (assoc kind ref-counts :test #'eq)) 0))
                           (cand-n (or (cdr (assoc kind cand-counts :test #'eq)) 0)))
                       (evaluate-kind-parity kind ref-n cand-n tolerance)))
                   all-seen-kinds))
         (pass-n (count :pass entries :key #'ae-verdict))
         (fail-n (count :fail entries :key #'ae-verdict))
         (skip-n (count :skip entries :key #'ae-verdict))
         ;; Overall: fail if any entry fails OR if diff-level tolerance exceeded
         (diff-ok (and (<= (tdr-mismatched-count diff) (tol-max-mismatches tolerance))
                       (<= (+ (tdr-missing-left diff) (tdr-missing-right diff))
                           (tol-max-missing tolerance))))
         (overall (if (and (zerop fail-n) diff-ok) :pass :fail)))
    (make-parity-assertion-report
     :report-id (compute-report-id (ap-name profile) timestamp)
     :profile-name (ap-name profile)
     :target (ap-target profile)
     :entries entries
     :pass-count pass-n
     :fail-count fail-n
     :skip-count skip-n
     :overall-verdict overall
     :diff-summary diff
     :timestamp timestamp)))

;;; ─── Predicates ───

(declaim (ftype (function (parity-assertion-report) (values boolean &optional))
                parity-report-pass-p))
(defun parity-report-pass-p (report)
  "Check if a parity assertion report passed. Pure."
  (declare (optimize (safety 3)))
  (eq :pass (par-overall-verdict report)))

;;; ─── JSON Serialization ───

(declaim (ftype (function (assertion-entry) (values string &optional))
                assertion-entry->json))
(defun assertion-entry->json (entry)
  "Serialize assertion-entry to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"kind\":\"~A\",\"expected\":~D,\"actual\":~D,\"verdict\":\"~A\",\"detail\":\"~A\"}"
          (ae-kind-label entry)
          (ae-expected-count entry)
          (ae-actual-count entry)
          (ae-verdict entry)
          (ae-detail entry)))

(declaim (ftype (function (parity-assertion-report) (values string &optional))
                parity-assertion-report->json))
(defun parity-assertion-report->json (report)
  "Serialize parity-assertion-report to JSON. Pure."
  (declare (optimize (safety 3)))
  (let ((entries-json
          (format nil "[~{~A~^,~}]"
                  (mapcar #'assertion-entry->json (par-entries report)))))
    (format nil "{\"report_id\":\"~A\",\"profile\":\"~A\",\"target\":\"~A\",\"entries\":~A,\"pass\":~D,\"fail\":~D,\"skip\":~D,\"verdict\":\"~A\",\"diff\":~A,\"timestamp\":~D}"
            (par-report-id report)
            (par-profile-name report)
            (par-target report)
            entries-json
            (par-pass-count report)
            (par-fail-count report)
            (par-skip-count report)
            (par-overall-verdict report)
            (trace-diff->json (par-diff-summary report))
            (par-timestamp report))))
