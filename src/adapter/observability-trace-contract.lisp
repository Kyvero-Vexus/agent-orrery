;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; observability-trace-contract.lisp — Cross-UI observability trace contract
;;;
;;; Defines typed contracts specifying which trace events each UI adapter
;;; (TUI/Web/McCLIM) MUST emit, a collector protocol for accumulating
;;; traces from multiple adapters, and a contract verifier that produces
;;; structured pass/fail verdicts per adapter.
;;;
;;; Builds on event-trace-canon (v4o) and parity-assertion (5nl).
;;; Bead: agent-orrery-eb0.6.6

(in-package #:orrery/adapter)

;;; ─── Trace Obligation ───
;;; A single requirement: "adapter X must emit events of kind K from source S"

(defstruct (trace-obligation (:conc-name tobl-))
  "A single obligation in a trace contract."
  (event-kind   :session :type event-kind)
  (source-tag   :adapter :type source-tag)
  (min-count    1        :type fixnum)
  (description  ""       :type string))

;;; ─── Trace Contract ───
;;; A named set of obligations for a specific UI target.

(defstruct (trace-contract (:conc-name tc-))
  "Typed contract specifying required trace emissions for a UI adapter."
  (name         ""   :type string)
  (target       :tui :type ui-target)
  (obligations  nil  :type list)      ; list of trace-obligation
  (version      1    :type fixnum))

;;; ─── Obligation Verdict ───

(deftype obligation-verdict ()
  '(member :satisfied :violated :exceeded))

(defstruct (obligation-result (:conc-name obr-))
  "Result of checking a single obligation against actual trace data."
  (obligation   (make-trace-obligation) :type trace-obligation)
  (actual-count 0   :type fixnum)
  (verdict      :satisfied :type obligation-verdict)
  (detail       ""  :type string))

;;; ─── Contract Verification Report ───

(defstruct (contract-verification (:conc-name cv-))
  "Full verification report for a trace contract against collected data."
  (contract-name  "" :type string)
  (target         :tui :type ui-target)
  (results        nil :type list)    ; list of obligation-result
  (satisfied-count 0  :type fixnum)
  (violated-count  0  :type fixnum)
  (exceeded-count  0  :type fixnum)
  (overall-pass-p  t  :type boolean)
  (timestamp       0  :type fixnum))

;;; ─── Trace Collector ───
;;; Accumulates trace events keyed by UI target.

(defstruct (trace-collector (:conc-name tcol-))
  "Accumulates trace streams from multiple UI adapters."
  (streams nil :type list)   ; alist of (ui-target . trace-stream)
  (count    0  :type fixnum))

;;; ─── Standard Contracts ───

(defun make-core-obligations ()
  "Obligations every UI adapter must satisfy. Pure."
  (declare (optimize (safety 3)))
  (list
   (make-trace-obligation :event-kind :session :source-tag :adapter
                          :min-count 1
                          :description "Adapter must emit session events")
   (make-trace-obligation :event-kind :cron :source-tag :adapter
                          :min-count 1
                          :description "Adapter must emit cron events")
   (make-trace-obligation :event-kind :health :source-tag :adapter
                          :min-count 1
                          :description "Adapter must emit health events")
   (make-trace-obligation :event-kind :alert :source-tag :adapter
                          :min-count 1
                          :description "Adapter must emit alert events")))

(defun make-tui-contract ()
  "Trace contract for the TUI adapter. Pure."
  (declare (optimize (safety 3)))
  (make-trace-contract
   :name "tui-observability-v1"
   :target :tui
   :obligations (append
                 (make-core-obligations)
                 (list
                  (make-trace-obligation
                   :event-kind :lifecycle :source-tag :adapter
                   :min-count 1
                   :description "TUI must emit lifecycle events for shell transitions")))
   :version 1))

(defun make-web-contract ()
  "Trace contract for the Web adapter. Pure."
  (declare (optimize (safety 3)))
  (make-trace-contract
   :name "web-observability-v1"
   :target :web
   :obligations (append
                 (make-core-obligations)
                 (list
                  (make-trace-obligation
                   :event-kind :probe :source-tag :adapter
                   :min-count 1
                   :description "Web must emit probe events for endpoint health")))
   :version 1))

(defun make-mcclim-contract ()
  "Trace contract for the McCLIM adapter. Pure."
  (declare (optimize (safety 3)))
  (make-trace-contract
   :name "mcclim-observability-v1"
   :target :mcclim
   :obligations (make-core-obligations)
   :version 1))

(defvar *standard-trace-contracts*
  (list (make-tui-contract)
        (make-web-contract)
        (make-mcclim-contract))
  "Standard trace contracts for all three UI adapters.")

;;; ─── Collector Operations ───

(declaim (ftype (function () (values trace-collector &optional))
                make-empty-collector))
(defun make-empty-collector ()
  "Create an empty trace collector. Pure."
  (declare (optimize (safety 3)))
  (make-trace-collector :streams nil :count 0))

(declaim (ftype (function (trace-collector ui-target trace-stream)
                          (values trace-collector &optional))
                collector-register-stream))
(defun collector-register-stream (collector target stream)
  "Register a trace stream for a UI target. Pure (returns new collector)."
  (declare (optimize (safety 3)))
  (let ((new-streams (cons (cons target stream)
                           (remove target (tcol-streams collector)
                                   :key #'car :test #'eq))))
    (make-trace-collector :streams new-streams
                          :count (length new-streams))))

(declaim (ftype (function (trace-collector ui-target)
                          (values (or trace-stream null) &optional))
                collector-get-stream))
(defun collector-get-stream (collector target)
  "Get the trace stream for a UI target. Pure."
  (declare (optimize (safety 3)))
  (cdr (assoc target (tcol-streams collector) :test #'eq)))

;;; ─── Obligation Checking ───

(declaim (ftype (function (trace-obligation trace-stream)
                          (values obligation-result &optional))
                check-obligation))
(defun check-obligation (obligation stream)
  "Check a single obligation against a trace stream. Pure."
  (declare (optimize (safety 3)))
  (let* ((kind (tobl-event-kind obligation))
         (source (tobl-source-tag obligation))
         (min-n (tobl-min-count obligation))
         (actual (count-if (lambda (ev)
                             (and (eq (tev-event-kind ev) kind)
                                  (eq (tev-source-tag ev) source)))
                           (ts-events stream)))
         (verdict (cond
                    ((< actual min-n) :violated)
                    ((> actual (* min-n 10)) :exceeded)
                    (t :satisfied)))
         (detail (format nil "~A/~A from ~A: need>=~D got=~D"
                         kind source (tobl-description obligation)
                         min-n actual)))
    (make-obligation-result
     :obligation obligation
     :actual-count actual
     :verdict verdict
     :detail detail)))

;;; ─── Full Contract Verification ───

(declaim (ftype (function (trace-contract trace-stream fixnum)
                          (values contract-verification &optional))
                verify-trace-contract))
(defun verify-trace-contract (contract stream timestamp)
  "Verify all obligations in a trace contract against a stream. Pure."
  (declare (optimize (safety 3)))
  (let* ((results (mapcar (lambda (obl) (check-obligation obl stream))
                          (tc-obligations contract)))
         (sat (count :satisfied results :key #'obr-verdict))
         (viol (count :violated results :key #'obr-verdict))
         (exc (count :exceeded results :key #'obr-verdict)))
    (make-contract-verification
     :contract-name (tc-name contract)
     :target (tc-target contract)
     :results results
     :satisfied-count sat
     :violated-count viol
     :exceeded-count exc
     :overall-pass-p (zerop viol)
     :timestamp timestamp)))

;;; ─── Multi-Adapter Verification ───

(declaim (ftype (function (trace-collector list fixnum)
                          (values list &optional))
                verify-all-contracts))
(defun verify-all-contracts (collector contracts timestamp)
  "Verify all contracts against their respective streams. Pure.
Returns list of contract-verification."
  (declare (optimize (safety 3)))
  (mapcar (lambda (contract)
            (let ((stream (collector-get-stream collector (tc-target contract))))
              (if stream
                  (verify-trace-contract contract stream timestamp)
                  ;; No stream registered: all obligations violated
                  (make-contract-verification
                   :contract-name (tc-name contract)
                   :target (tc-target contract)
                   :results (mapcar (lambda (obl)
                                      (make-obligation-result
                                       :obligation obl
                                       :actual-count 0
                                       :verdict :violated
                                       :detail "No trace stream registered"))
                                    (tc-obligations contract))
                   :satisfied-count 0
                   :violated-count (length (tc-obligations contract))
                   :exceeded-count 0
                   :overall-pass-p nil
                   :timestamp timestamp))))
          contracts))

;;; ─── Cross-UI Parity via Contracts ───

(declaim (ftype (function (trace-collector fixnum)
                          (values list &optional))
                cross-ui-parity-matrix))
(defun cross-ui-parity-matrix (collector timestamp)
  "Run parity assertions for every pair of registered UI targets. Pure.
Returns list of parity-assertion-report."
  (declare (optimize (safety 3)))
  (let ((targets (mapcar #'car (tcol-streams collector)))
        (reports nil))
    (loop :for (a . rest) :on targets
          :do (loop :for b :in rest
                    :for a-stream := (collector-get-stream collector a)
                    :for b-stream := (collector-get-stream collector b)
                    :for profile := (make-assertion-profile
                                     :name (format nil "~A-vs-~A" a b)
                                     :target a
                                     :tolerance (make-tolerance-spec
                                                 :max-mismatches 0
                                                 :max-missing 2
                                                 :required-kinds '(:session :cron :health :alert))
                                     :required-sources *all-sources*)
                    :when (and a-stream b-stream)
                      :do (push (run-parity-assertion profile a-stream b-stream timestamp)
                                reports)))
    (nreverse reports)))

;;; ─── JSON Serialization ───

(declaim (ftype (function (obligation-result) (values string &optional))
                obligation-result->json))
(defun obligation-result->json (result)
  "Serialize obligation-result to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"kind\":\"~A\",\"source\":\"~A\",\"min\":~D,\"actual\":~D,\"verdict\":\"~A\",\"detail\":\"~A\"}"
          (tobl-event-kind (obr-obligation result))
          (tobl-source-tag (obr-obligation result))
          (tobl-min-count (obr-obligation result))
          (obr-actual-count result)
          (obr-verdict result)
          (obr-detail result)))

(declaim (ftype (function (contract-verification) (values string &optional))
                contract-verification->json))
(defun contract-verification->json (cv)
  "Serialize contract-verification to JSON. Pure."
  (declare (optimize (safety 3)))
  (let ((results-json (format nil "[~{~A~^,~}]"
                              (mapcar #'obligation-result->json (cv-results cv)))))
    (format nil "{\"contract\":\"~A\",\"target\":\"~A\",\"results\":~A,\"satisfied\":~D,\"violated\":~D,\"exceeded\":~D,\"pass\":~A,\"timestamp\":~D}"
            (cv-contract-name cv)
            (cv-target cv)
            results-json
            (cv-satisfied-count cv)
            (cv-violated-count cv)
            (cv-exceeded-count cv)
            (if (cv-overall-pass-p cv) "true" "false")
            (cv-timestamp cv))))
