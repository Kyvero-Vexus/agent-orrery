;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-orchestrator.lisp — Gate-resolution orchestrator for Epic 2
;;;
;;; Consumes decision artifacts and performs deterministic routing:
;;; close gate on pass, emit blocker report, or open remediation chain.

(in-package #:orrery/adapter)

;;; ─── Resolution Actions ───

(deftype resolution-action ()
  '(member :close-gate :emit-blocker-report :open-remediation-chain
           :escalate-to-human))

;;; ─── Remediation Chain Entry ───

(defstruct (remediation-step
             (:constructor make-remediation-step
                 (&key step-id action-type target description
                       depends-on))
             (:conc-name rs-))
  "One step in a remediation chain."
  (step-id "" :type string)
  (action-type :manual :type keyword)
  (target "" :type string)
  (description "" :type string)
  (depends-on '() :type list))

;;; ─── Resolution Plan ───

(defstruct (resolution-plan
             (:constructor make-resolution-plan
                 (&key decision-gate-id primary-action
                       remediation-steps blocker-report
                       unblock-targets timestamp))
             (:conc-name rp-))
  "Complete resolution plan from decision artifact."
  (decision-gate-id "" :type string)
  (primary-action :escalate-to-human :type resolution-action)
  (remediation-steps '() :type list)
  (blocker-report "" :type string)
  (unblock-targets '() :type list)
  (timestamp 0 :type integer))

;;; ─── Orchestrator ───

(declaim (ftype (function (gate-decision-record) (values resolution-plan &optional))
                orchestrate-resolution)
         (ftype (function (resolution-plan) (values string &optional))
                resolution-plan-to-json))

(defun %build-pass-steps (record)
  "Build steps for pass resolution."
  (declare (type gate-decision-record record))
  (declare (ignorable record))
  (list (make-remediation-step
         :step-id "close-eb0.2.5"
         :action-type :bead-close
         :target "agent-orrery-eb0.2.5"
         :description "Close S1 gate with pass evidence"
         :depends-on '())
        (make-remediation-step
         :step-id "unblock-eb0.2"
         :action-type :bead-update
         :target "agent-orrery-eb0.2"
         :description "Mark Epic 2 adapter gate as resolved"
         :depends-on '("close-eb0.2.5"))
        (make-remediation-step
         :step-id "signal-epic3"
         :action-type :signal
         :target "epic-3"
         :description "Signal Epic 3 (TUI) ready for kickoff"
         :depends-on '("unblock-eb0.2"))
        (make-remediation-step
         :step-id "signal-epic4"
         :action-type :signal
         :target "epic-4"
         :description "Signal Epic 4 (Web) ready for kickoff"
         :depends-on '("unblock-eb0.2"))
        (make-remediation-step
         :step-id "signal-epic5"
         :action-type :signal
         :target "epic-5"
         :description "Signal Epic 5 (McCLIM) ready for kickoff"
         :depends-on '("unblock-eb0.2"))))

(defun %build-blocker-report (record)
  "Build human-readable blocker report."
  (declare (type gate-decision-record record))
  (with-output-to-string (s)
    (format s "S1 GATE BLOCKER REPORT~%")
    (format s "======================~%")
    (format s "Decision: ~A~%" (gdr-outcome record))
    (format s "Reason: ~A~%" (gdr-reason record))
    (format s "Blockers: ~D~%~%" (gdr-blocker-count record))
    (format s "REQUIRED ACTIONS (ordered by urgency):~%")
    (let ((n 0))
      (dolist (a (gdr-next-actions record))
        (incf n)
        (format s "~D. [~A] ~A (owner: ~A)~%"
                n (na-urgency a) (na-description a) (na-owner a))))))

(defun %build-blocked-external-steps (record)
  "Build steps for external blocker resolution."
  (declare (type gate-decision-record record))
  (let ((steps '())
        (n 0))
    (dolist (a (gdr-next-actions record))
      (incf n)
      (push (make-remediation-step
             :step-id (format nil "ext-~D-~A" n (na-action-id a))
             :action-type :external-action
             :target (na-owner a)
             :description (na-description a)
             :depends-on (when (> n 1)
                           (list (format nil "ext-~D-~A"
                                         (1- n) (na-action-id
                                                  (nth (- n 2)
                                                       (gdr-next-actions record)))))))
            steps))
    (nreverse steps)))

(defun %build-contract-steps (record)
  "Build steps for contract remediation chain."
  (declare (type gate-decision-record record))
  (let ((steps '())
        (n 0))
    (dolist (a (gdr-next-actions record))
      (incf n)
      (push (make-remediation-step
             :step-id (format nil "contract-~D-~A" n (na-action-id a))
             :action-type :code-fix
             :target "gensym"
             :description (na-description a)
             :depends-on (when (> n 1)
                           (list (format nil "contract-~D-~A"
                                         (1- n) (na-action-id
                                                  (nth (- n 2)
                                                       (gdr-next-actions record)))))))
            steps))
    (nreverse steps)))

(defun orchestrate-resolution (record)
  "Orchestrate gate resolution from decision record."
  (declare (type gate-decision-record record))
  (let* ((outcome (gdr-outcome record))
         (primary (case outcome
                    (:pass :close-gate)
                    (:blocked-external :emit-blocker-report)
                    (:blocked-contract :open-remediation-chain)
                    (otherwise :escalate-to-human)))
         (steps (case outcome
                  (:pass (%build-pass-steps record))
                  (:blocked-external (%build-blocked-external-steps record))
                  (:blocked-contract (%build-contract-steps record))
                  (otherwise
                   (list (make-remediation-step
                          :step-id "escalate"
                          :action-type :manual
                          :target "ceo"
                          :description "Inconclusive — manual review required")))))
         (unblocks (when (eq :pass outcome)
                     '("epic-3" "epic-4" "epic-5"))))
    (make-resolution-plan
     :decision-gate-id (gdr-gate-id record)
     :primary-action primary
     :remediation-steps steps
     :blocker-report (if (eq :pass outcome) ""
                         (%build-blocker-report record))
     :unblock-targets unblocks
     :timestamp (get-universal-time))))

;;; ─── JSON Serialization ───

(defun resolution-plan-to-json (plan)
  "Serialize resolution plan to deterministic JSON."
  (declare (type resolution-plan plan))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"decision_gate_id\":" s)
    (emit-json-string (rp-decision-gate-id plan) s)
    (write-string ",\"primary_action\":" s)
    (emit-json-string (string-downcase (symbol-name (rp-primary-action plan))) s)
    (write-string ",\"unblock_targets\":[" s)
    (let ((first t))
      (dolist (u (rp-unblock-targets plan))
        (unless first (write-char #\, s))
        (setf first nil)
        (emit-json-string u s)))
    (write-string "],\"remediation_steps\":[" s)
    (let ((first t))
      (dolist (step (rp-remediation-steps plan))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"step_id\":" s)
        (emit-json-string (rs-step-id step) s)
        (write-string ",\"action_type\":" s)
        (emit-json-string (string-downcase (symbol-name (rs-action-type step))) s)
        (write-string ",\"target\":" s)
        (emit-json-string (rs-target step) s)
        (write-string ",\"description\":" s)
        (emit-json-string (rs-description step) s)
        (write-string ",\"depends_on\":[" s)
        (let ((first-d t))
          (dolist (d (rs-depends-on step))
            (unless first-d (write-char #\, s))
            (setf first-d nil)
            (emit-json-string d s)))
        (write-string "]}" s)))
    (write-string "]}" s)))
