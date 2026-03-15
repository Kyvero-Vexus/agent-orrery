;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-orchestration-runner.lisp — Epic-2 gate orchestration runner
;;;
;;; Composes capture → corpus → parity → verdict pipeline.

(in-package #:orrery/adapter)

;;; ─── Types ───

(deftype run-profile ()
  '(member :fixture :live :hybrid))

(deftype step-status ()
  '(member :pass :fail :skip :error))

(defstruct (gate-run-config (:conc-name grc-))
  "Configuration for a gate run."
  (profile    :fixture :type run-profile)
  (endpoints  nil     :type list)
  (seed       0       :type fixnum)
  (verbose-p  nil     :type boolean))

(defstruct (gate-step-result (:conc-name gsr-))
  "Result of a single gate step."
  (step-name "" :type string)
  (status :pass :type step-status)
  (duration-ms 0 :type fixnum)
  (artifact nil :type t)
  (message  "" :type string))

(defstruct (gate-run-report (:conc-name grr-))
  "Complete gate run report."
  (config nil :type (or null gate-run-config))
  (steps nil :type list)
  (verdict :pass :type step-status)
  (total-duration-ms 0 :type fixnum)
  (step-count 0 :type fixnum))

;;; ─── Default Config ───

(declaim (ftype (function (run-profile &key (:seed fixnum))
                          (values gate-run-config &optional))
                make-default-config))
(defun make-default-config (profile &key (seed 0))
  "Create default gate run configuration. Pure."
  (declare (optimize (safety 3)))
  (make-gate-run-config
   :profile profile
   :endpoints '("/api/v1/sessions" "/api/v1/cron" "/api/v1/health"
                "/api/v1/events" "/api/v1/alerts" "/api/v1/usage")
   :seed seed
   :verbose-p nil))

;;; ─── Step Execution ───

(declaim (ftype (function (gate-run-config)
                          (values gate-step-result &optional))
                run-capture-step))
(defun run-capture-step (config)
  "Execute capture step: generate fixture snapshots. Pure for fixture profile."
  (declare (optimize (safety 3)))
  (let* ((endpoints (grc-endpoints config))
         (profile (grc-profile config))
         (entries (loop :for ep :in endpoints
                        :for idx :from 0
                        :collect (make-corpus-entry-from-sample
                                  ep :session
                                  (format nil "{\"fixture\":true,\"endpoint\":\"~A\",\"profile\":\"~A\"}"
                                          ep profile)
                                  idx))))
    (make-gate-step-result
     :step-name "capture"
     :status :pass
     :duration-ms 0
     :artifact entries
     :message (format nil "Captured ~D endpoints" (length entries)))))

(declaim (ftype (function (gate-run-config list)
                          (values gate-step-result &optional))
                run-corpus-step))
(defun run-corpus-step (config entries)
  "Build corpus from captured entries. Pure."
  (declare (optimize (safety 3)))
  (let ((corpus (build-corpus entries
                              :version 1
                              :seed (grc-seed config))))
    (make-gate-step-result
     :step-name "corpus"
     :status (if (> (cman-entry-count corpus) 0) :pass :fail)
     :duration-ms 0
     :artifact corpus
     :message (format nil "Built corpus: ~D entries, checksum ~D"
                      (cman-entry-count corpus) (cman-checksum corpus)))))

(declaim (ftype (function (corpus-manifest corpus-manifest)
                          (values gate-step-result &optional))
                run-parity-step))
(defun run-parity-step (current baseline)
  "Compare corpus against baseline for regressions. Pure."
  (declare (optimize (safety 3)))
  (let* ((diff (diff-corpora baseline current))
         (stable (and (zerop (cdiff-removed diff))
                      (zerop (cdiff-changed diff)))))
    (make-gate-step-result
     :step-name "parity"
     :status (if stable :pass :fail)
     :duration-ms 0
     :artifact diff
     :message (format nil "Parity: ~A (added:~D removed:~D changed:~D unchanged:~D)"
                      (if stable "STABLE" "REGRESSION")
                      (cdiff-added diff) (cdiff-removed diff)
                      (cdiff-changed diff) (cdiff-unchanged diff)))))

(declaim (ftype (function (list) (values gate-step-result &optional))
                run-verdict-step))
(defun run-verdict-step (prior-steps)
  "Compute final verdict from step results. Pure."
  (declare (optimize (safety 3)))
  (let* ((any-fail (some (lambda (s) (eq (gsr-status s) :fail)) prior-steps))
         (any-error (some (lambda (s) (eq (gsr-status s) :error)) prior-steps))
         (verdict (cond (any-error :error)
                        (any-fail :fail)
                        (t :pass))))
    (make-gate-step-result
     :step-name "verdict"
     :status verdict
     :duration-ms 0
     :artifact nil
     :message (format nil "Gate verdict: ~A (~D steps evaluated)"
                      verdict (length prior-steps)))))

;;; ─── Full Pipeline ───

(declaim (ftype (function (gate-run-config &key (:baseline (or null corpus-manifest)))
                          (values gate-run-report &optional))
                execute-gate-run))
(defun execute-gate-run (config &key baseline)
  "Execute complete gate pipeline. Pure for fixture profile."
  (declare (optimize (safety 3)))
  (let* ((capture-result (run-capture-step config))
         (entries (gsr-artifact capture-result))
         (corpus-result (run-corpus-step config entries))
         (corpus (gsr-artifact corpus-result))
         (parity-result (if baseline
                            (run-parity-step corpus baseline)
                            (make-gate-step-result
                             :step-name "parity"
                             :status :skip
                             :message "No baseline — first run")))
         (steps (list capture-result corpus-result parity-result))
         (verdict-result (run-verdict-step steps))
         (all-steps (append steps (list verdict-result))))
    (make-gate-run-report
     :config config
     :steps all-steps
     :verdict (gsr-status verdict-result)
     :total-duration-ms 0
     :step-count (length all-steps))))

;;; ─── JSON Serialization ───

(declaim (ftype (function (gate-step-result) (values string &optional))
                gate-step->json))
(defun gate-step->json (step)
  "Serialize step result to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"step\":\"~A\",\"status\":\"~A\",\"duration_ms\":~D,\"message\":\"~A\"}"
          (gsr-step-name step) (gsr-status step)
          (gsr-duration-ms step) (gsr-message step)))

(declaim (ftype (function (gate-run-report) (values string &optional))
                gate-run->json))
(defun gate-run->json (report)
  "Serialize gate run report to JSON. Pure."
  (declare (optimize (safety 3)))
  (format nil "{\"verdict\":\"~A\",\"step_count\":~D,\"total_duration_ms\":~D,\"profile\":\"~A\",\"steps\":[~{~A~^,~}]}"
          (grr-verdict report) (grr-step-count report)
          (grr-total-duration-ms report)
          (grc-profile (grr-config report))
          (mapcar #'gate-step->json (grr-steps report))))
