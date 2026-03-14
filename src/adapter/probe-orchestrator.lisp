;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; probe-orchestrator.lisp — Typed live-target probe orchestrator for S1 gating
;;;
;;; Runs fixture/live/probe-only contract suites for Scenario S1,
;;; classifies transport/auth/content-type failures, emits normalized
;;; machine-readable gate verdicts.

(in-package #:orrery/adapter)

;;; ─── Failure Classification ───

(deftype failure-class ()
  '(member :transport :auth :content-type :schema :none))

(defstruct (classified-failure
             (:constructor make-classified-failure
                 (&key failure-class check remediation))
             (:conc-name cf-))
  "A contract check failure with classified root cause."
  (failure-class :none :type failure-class)
  (check nil :type (or null contract-check))
  (remediation "" :type string))

;;; ─── S1 Gate Verdict ───

(deftype s1-verdict ()
  '(member :gate-pass :gate-fail-transport :gate-fail-auth
           :gate-fail-content :gate-fail-schema :gate-skip))

(defstruct (s1-gate-result
             (:constructor make-s1-gate-result
                 (&key verdict profile harness-result
                       classified-failures diagnostics))
             (:conc-name s1-))
  "Complete S1 gate result with classified failures and diagnostics."
  (verdict :gate-skip :type s1-verdict)
  (profile :fixture :type target-profile)
  (harness-result nil :type (or null harness-result))
  (classified-failures '() :type list)
  (diagnostics '() :type list))

;;; ─── Failure Classifier ───

(declaim (ftype (function (contract-check) (values classified-failure &optional))
                classify-check-failure)
         (ftype (function (runtime-target) (values s1-gate-result &optional))
                run-s1-probe)
         (ftype (function (s1-gate-result) (values string &optional))
                s1-gate-result-to-json))

(defun classify-check-failure (check)
  "Classify a failed contract check into a failure category."
  (declare (type contract-check check))
  (let ((msg (cc-message check))
        (name (cc-endpoint-name check)))
    (cond
      ;; Content-type failures (HTML instead of JSON) — check before transport
      ((or (search "HTML" msg) (search "html" msg)
           (search "text/html" msg))
       (make-classified-failure
        :failure-class :content-type
        :check check
        :remediation "Endpoint returns HTML. Configure API-mode endpoint or use /api/v1/ prefix"))
      ;; Auth failures
      ((or (search "401" msg) (search "403" msg)
           (search "unauthorized" msg) (search "token" msg))
       (make-classified-failure
        :failure-class :auth
        :check check
        :remediation "Set ORRERY_OPENCLAW_TOKEN with valid credentials"))
      ;; Transport failures
      ((or (search "not accessible" msg)
           (search "unreachable" msg)
           (search "ORRERY_OPENCLAW_BASE_URL" msg))
       (make-classified-failure
        :failure-class :transport
        :check check
        :remediation "Set ORRERY_OPENCLAW_BASE_URL to a reachable OpenClaw JSON API endpoint"))
      ;; Schema mismatch
      ((or (search "required-keys" msg) (search "schema" msg)
           (search "missing" msg))
       (make-classified-failure
        :failure-class :schema
        :check check
        :remediation (format nil "Endpoint ~A returned unexpected schema" name)))
      ;; Unknown
      (t
       (make-classified-failure
        :failure-class :transport
        :check check
        :remediation (format nil "Unclassified failure on ~A: ~A" name msg))))))

;;; ─── S1 Probe Orchestrator ───

(defun run-s1-probe (target)
  "Run the full S1 gate probe against a runtime target.
   Orchestrates contract harness, classifies failures, produces gate verdict."
  (declare (type runtime-target target))
  (let* ((result (run-contract-harness target *standard-contracts*))
         (failures '())
         (diagnostics '()))
    ;; Classify each failed check
    (dolist (check (chr-checks result))
      (when (eq :fail (cc-verdict check))
        (push (classify-check-failure check) failures)))
    ;; Build diagnostics
    (push (format nil "Profile: ~A" (rt-profile target)) diagnostics)
    (push (format nil "Checks: ~D pass, ~D fail, ~D skip"
                  (chr-pass-count result) (chr-fail-count result) (chr-skip-count result))
          diagnostics)
    (when failures
      (push (format nil "Primary failure class: ~A"
                    (cf-failure-class (first failures)))
            diagnostics))
    ;; Determine verdict
    (let ((verdict
            (cond
              ((zerop (chr-fail-count result))
               (if (plusp (chr-pass-count result)) :gate-pass :gate-skip))
              ((some (lambda (f) (eq :transport (cf-failure-class f))) failures)
               :gate-fail-transport)
              ((some (lambda (f) (eq :auth (cf-failure-class f))) failures)
               :gate-fail-auth)
              ((some (lambda (f) (eq :content-type (cf-failure-class f))) failures)
               :gate-fail-content)
              ((some (lambda (f) (eq :schema (cf-failure-class f))) failures)
               :gate-fail-schema)
              (t :gate-fail-transport))))
      (make-s1-gate-result
       :verdict verdict
       :profile (rt-profile target)
       :harness-result result
       :classified-failures (nreverse failures)
       :diagnostics (nreverse diagnostics)))))

;;; ─── JSON Serialization ───

(defun s1-gate-result-to-json (result)
  "Serialize S1 gate result to deterministic JSON."
  (declare (type s1-gate-result result))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"verdict\":" s)
    (emit-json-string (string-downcase (symbol-name (s1-verdict result))) s)
    (write-string ",\"profile\":" s)
    (emit-json-string (string-downcase (symbol-name (s1-profile result))) s)
    (write-string ",\"failures\":[" s)
    (let ((first t))
      (dolist (f (s1-classified-failures result))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"class\":" s)
        (emit-json-string (string-downcase (symbol-name (cf-failure-class f))) s)
        (write-string ",\"endpoint\":" s)
        (emit-json-string (if (cf-check f) (cc-endpoint-name (cf-check f)) "") s)
        (write-string ",\"remediation\":" s)
        (emit-json-string (cf-remediation f) s)
        (write-string "}" s)))
    (write-string "]" s)
    (write-string ",\"diagnostics\":[" s)
    (let ((first t))
      (dolist (d (s1-diagnostics result))
        (unless first (write-char #\, s))
        (setf first nil)
        (emit-json-string d s)))
    (write-string "]}" s)))
