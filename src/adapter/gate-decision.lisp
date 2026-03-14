;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-decision.lisp — S1 gate decision engine
;;;
;;; Consumes evidence bundle + conformance + drift outputs and returns
;;; deterministic gate outcomes with ordered next-action plans.

(in-package #:orrery/adapter)

;;; ─── Decision Outcome ───

(deftype gate-outcome ()
  '(member :pass :blocked-external :blocked-contract :escalate))

(deftype action-urgency ()
  '(member :immediate :next-session :backlog))

;;; ─── Next Action ───

(defstruct (next-action
             (:constructor make-next-action
                 (&key action-id urgency description owner))
             (:conc-name na-))
  "One remediation action in the ordered plan."
  (action-id "" :type string)
  (urgency :immediate :type action-urgency)
  (description "" :type string)
  (owner "" :type string))

;;; ─── Gate Decision Record ───

(defstruct (gate-decision-record
             (:constructor make-gate-decision-record
                 (&key gate-id outcome reason next-actions
                       evidence-gate-id blocker-count
                       can-close-gate-p timestamp))
             (:conc-name gdr-))
  "Complete decision record for S1 gate."
  (gate-id "" :type string)
  (outcome :escalate :type gate-outcome)
  (reason "" :type string)
  (next-actions '() :type list)
  (evidence-gate-id "" :type string)
  (blocker-count 0 :type fixnum)
  (can-close-gate-p nil :type boolean)
  (timestamp 0 :type integer))

;;; ─── Decision Engine ───

(declaim (ftype (function (evidence-bundle) (values gate-decision-record &optional))
                decide-s1-gate)
         (ftype (function (gate-decision-record) (values string &optional))
                gate-decision-to-json))

(defun %build-next-actions (bundle outcome)
  "Build ordered next-action plan based on outcome and blockers."
  (declare (type evidence-bundle bundle) (type gate-outcome outcome))
  (case outcome
    (:pass
     (list (make-next-action
            :action-id "close-gate"
            :urgency :immediate
            :description "Close eb0.2.5 with pass evidence"
            :owner "gensym")
           (make-next-action
            :action-id "unblock-epics"
            :urgency :immediate
            :description "Unblock downstream epics 3-6"
            :owner "ceo")))
    (:blocked-external
     (let ((actions '()))
       ;; Check specific blocker classes
       (dolist (b (eb-blockers bundle))
         (case (be-blocker-class b)
           (:transport
            (push (make-next-action
                   :action-id "provide-endpoint"
                   :urgency :immediate
                   :description "Set ORRERY_OPENCLAW_BASE_URL to reachable JSON API"
                   :owner "ceo")
                  actions))
           (:auth
            (push (make-next-action
                   :action-id "provide-token"
                   :urgency :immediate
                   :description "Set ORRERY_OPENCLAW_TOKEN with valid credentials"
                   :owner "ceo")
                  actions))
           (:external-runtime
            (push (make-next-action
                   :action-id "fix-runtime"
                   :urgency :immediate
                   :description (format nil "Fix external runtime: ~A"
                                        (be-description b))
                   :owner "ceo")
                  actions))))
       ;; Always add re-probe action
       (push (make-next-action
              :action-id "re-probe"
              :urgency :next-session
              :description "Re-run S1 probe after blockers resolved"
              :owner "gensym")
             actions)
       (nreverse actions)))
    (:blocked-contract
     (let ((actions '()))
       (dolist (b (eb-blockers bundle))
         (when (eq :schema-drift (be-blocker-class b))
           (push (make-next-action
                  :action-id "fix-schema"
                  :urgency :immediate
                  :description (be-remediation-hint b)
                  :owner "gensym")
                 actions)))
       (push (make-next-action
              :action-id "re-validate"
              :urgency :next-session
              :description "Re-run conformance + drift checks"
              :owner "gensym")
             actions)
       (nreverse actions)))
    (:escalate
     (list (make-next-action
            :action-id "investigate"
            :urgency :immediate
            :description "Manual investigation required — inconclusive evidence"
            :owner "ceo")))))

(defun decide-s1-gate (bundle)
  "Determine S1 gate outcome from evidence bundle."
  (declare (type evidence-bundle bundle))
  (let* ((decision (eb-decision bundle))
         (outcome (case decision
                    (:pass :pass)
                    (:blocked-external :blocked-external)
                    (:fail :blocked-contract)
                    (otherwise :escalate)))
         (next-actions (%build-next-actions bundle outcome)))
    (make-gate-decision-record
     :gate-id (format nil "decision-~A" (eb-gate-id bundle))
     :outcome outcome
     :reason (case outcome
               (:pass "All S1 checks passed — fixture and/or live validated")
               (:blocked-external
                (format nil "~D external blocker(s): ~{~A~^, ~}"
                        (length (eb-blockers bundle))
                        (mapcar #'be-reason-code (eb-blockers bundle))))
               (:blocked-contract
                (format nil "Contract failures: ~A" (eb-conformance-summary bundle)))
               (:escalate "Inconclusive evidence — manual review needed"))
     :next-actions next-actions
     :evidence-gate-id (eb-gate-id bundle)
     :blocker-count (length (eb-blockers bundle))
     :can-close-gate-p (eq :pass outcome)
     :timestamp (get-universal-time))))

;;; ─── JSON Serialization ───

(defun gate-decision-to-json (record)
  "Serialize gate decision record to deterministic JSON."
  (declare (type gate-decision-record record))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"gate_id\":" s)
    (emit-json-string (gdr-gate-id record) s)
    (write-string ",\"outcome\":" s)
    (emit-json-string (string-downcase (symbol-name (gdr-outcome record))) s)
    (write-string ",\"reason\":" s)
    (emit-json-string (gdr-reason record) s)
    (write-string ",\"can_close_gate\":" s)
    (write-string (if (gdr-can-close-gate-p record) "true" "false") s)
    (write-string ",\"blocker_count\":" s)
    (format s "~D" (gdr-blocker-count record))
    (write-string ",\"evidence_gate_id\":" s)
    (emit-json-string (gdr-evidence-gate-id record) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (gdr-timestamp record))
    (write-string ",\"next_actions\":[" s)
    (let ((first t))
      (dolist (a (gdr-next-actions record))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"action_id\":" s)
        (emit-json-string (na-action-id a) s)
        (write-string ",\"urgency\":" s)
        (emit-json-string (string-downcase (symbol-name (na-urgency a))) s)
        (write-string ",\"description\":" s)
        (emit-json-string (na-description a) s)
        (write-string ",\"owner\":" s)
        (emit-json-string (na-owner a) s)
        (write-string "}" s)))
    (write-string "]}" s)))
