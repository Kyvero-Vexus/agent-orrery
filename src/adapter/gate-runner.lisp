;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; gate-runner.lisp — Typed CI preflight gate runner + failure policy matrix
;;;
;;; Invokes live-gate preflight, applies typed failure-policy matrix,
;;; emits machine-readable gate artifacts.

(in-package #:orrery/adapter)

;;; ─── Failure Policy ───

(deftype failure-action ()
  '(member :hard-fail :soft-fail :skip))

(defstruct (failure-policy
             (:constructor make-failure-policy
                 (&key check-name action rationale))
             (:conc-name fp-))
  "Policy for how to handle a specific check failure."
  (check-name "" :type string)
  (action :hard-fail :type failure-action)
  (rationale "" :type string))

(defstruct (gate-result
             (:constructor make-gate-result
                 (&key gate-passed-p applied-policies report exit-code))
             (:conc-name gr-))
  "Result of applying failure policy matrix to a preflight report."
  (gate-passed-p nil :type boolean)
  (applied-policies '() :type list)
  (report nil :type (or null preflight-report))
  (exit-code 0 :type fixnum))

;;; ─── Default Policy Matrix ───

(defparameter *default-failure-policies*
  (list
   ;; Health endpoints are hard-fail (must be accessible)
   (make-failure-policy :check-name "endpoint:/health"
                        :action :hard-fail
                        :rationale "Health endpoint required for liveness gate")
   ;; Session endpoints soft-fail (degraded mode OK)
   (make-failure-policy :check-name "endpoint:/sessions"
                        :action :soft-fail
                        :rationale "Session listing optional for basic health gate")
   ;; Unknown endpoints skip
   (make-failure-policy :check-name "endpoint:/unknown"
                        :action :skip
                        :rationale "Unknown endpoints not critical for gate"))
  "Default failure policy matrix for CI preflight gates.")

;;; ─── Gate Runner ───

(declaim (ftype (function (preflight-report list) (values gate-result &optional))
                apply-failure-policies)
         (ftype (function (string list &key (:policies list) (:check-fn t))
                          (values gate-result &optional))
                run-gate))

(defun apply-failure-policies (report policies)
  "Apply failure policy matrix to a preflight report.
   Returns gate-result with pass/fail + applied policy log."
  (declare (type preflight-report report) (type list policies))
  (let ((applied '())
        (has-hard-fail nil)
        (has-soft-fail nil))
    (dolist (check (pr-checks report))
      (when (eq :fail (pc-status check))
        (let ((policy (find (pc-name check) policies
                            :key #'fp-check-name :test #'string=)))
          (cond
            ((null policy)
             ;; No explicit policy → default hard-fail
             (setf has-hard-fail t)
             (push (make-failure-policy
                    :check-name (pc-name check)
                    :action :hard-fail
                    :rationale "No explicit policy — defaulting to hard-fail")
                   applied))
            ((eq :hard-fail (fp-action policy))
             (setf has-hard-fail t)
             (push policy applied))
            ((eq :soft-fail (fp-action policy))
             (setf has-soft-fail t)
             (push policy applied))
            ((eq :skip (fp-action policy))
             (push policy applied))))))
    (make-gate-result
     :gate-passed-p (not has-hard-fail)
     :applied-policies (nreverse applied)
     :report report
     :exit-code (cond (has-hard-fail 1)
                      (has-soft-fail 2)
                      (t 0)))))

(defun run-gate (base-url paths &key (policies *default-failure-policies*) (check-fn nil))
  "Run preflight and apply failure policy matrix. Returns gate-result."
  (declare (type string base-url) (type list paths))
  (let ((report (run-preflight base-url paths :check-fn check-fn)))
    (apply-failure-policies report policies)))
