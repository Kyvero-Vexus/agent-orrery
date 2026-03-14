;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; evidence-bundle.lisp — Typed evidence bundle + blocker taxonomy for S1 gate
;;;
;;; Packages fixture/live probe outputs into reproducible gate artifacts
;;; with categorized blocker taxonomy for decisioning.

(in-package #:orrery/adapter)

;;; ─── Blocker Taxonomy ───

(deftype blocker-class ()
  '(member :external-runtime :auth :transport :schema-drift :none))

(deftype blocker-resolution ()
  '(member :resolved :unresolved :deferred :not-applicable))

(defstruct (blocker-entry
             (:constructor make-blocker-entry
                 (&key blocker-class reason-code description
                       resolution remediation-hint))
             (:conc-name be-))
  "One classified blocker in the taxonomy."
  (blocker-class :external-runtime :type blocker-class)
  (reason-code "" :type string)
  (description "" :type string)
  (resolution :unresolved :type blocker-resolution)
  (remediation-hint "" :type string))

;;; ─── Evidence Bundle ───

(deftype gate-decision ()
  '(member :pass :fail :blocked-external :inconclusive))

(defstruct (evidence-bundle
             (:constructor make-evidence-bundle
                 (&key gate-id target-profile decision
                       s1-verdict conformance-summary
                       drift-compatible-p blockers
                       artifact-shas timestamp notes))
             (:conc-name eb-))
  "Complete evidence bundle for S1 gate decisioning."
  (gate-id "" :type string)
  (target-profile :fixture :type keyword)
  (decision :inconclusive :type gate-decision)
  (s1-verdict :gate-skip :type s1-verdict)
  (conformance-summary "" :type string)
  (drift-compatible-p t :type boolean)
  (blockers '() :type list)
  (artifact-shas '() :type list)
  (timestamp 0 :type integer)
  (notes "" :type string))

;;; ─── Blocker Classifier ───

(declaim (ftype (function (s1-gate-result conformance-check-result list)
                          (values list &optional))
                classify-blockers)
         (ftype (function (s1-gate-result conformance-check-result list
                           &key (:artifact-shas list))
                          (values evidence-bundle &optional))
                build-evidence-bundle)
         (ftype (function (evidence-bundle) (values string &optional))
                evidence-bundle-to-json))

(defun classify-blockers (s1-result conformance-result drift-reports)
  "Classify all blockers from probe/conformance/drift results into taxonomy."
  (declare (type s1-gate-result s1-result)
           (type conformance-check-result conformance-result)
           (type list drift-reports))
  (let ((blockers '()))
    ;; S1 gate failures → blocker entries
    (dolist (cf (s1-classified-failures s1-result))
      (push (make-blocker-entry
             :blocker-class (case (cf-failure-class cf)
                              (:transport :transport)
                              (:auth :auth)
                              (:content-type :external-runtime)
                              (:schema :schema-drift)
                              (otherwise :external-runtime))
             :reason-code (format nil "s1-~A"
                                  (string-downcase
                                   (symbol-name (cf-failure-class cf))))
             :description (cc-message (cf-check cf))
             :resolution :unresolved
             :remediation-hint (cf-remediation cf))
            blockers))
    ;; Conformance violations
    (dolist (v (ccr-violations conformance-result))
      (push (make-blocker-entry
             :blocker-class :external-runtime
             :reason-code "conformance-violation"
             :description v
             :resolution :unresolved
             :remediation-hint "Ensure endpoint coverage meets minimum requirements")
            blockers))
    ;; Schema drift
    (dolist (report drift-reports)
      (unless (dr-compatible-p report)
        (dolist (f (dr-findings report))
          (when (member (df-severity f) '(:breaking :degrading))
            (push (make-blocker-entry
                   :blocker-class :schema-drift
                   :reason-code (format nil "drift-~A"
                                        (string-downcase
                                         (symbol-name (df-drift-type f))))
                   :description (df-message f)
                   :resolution :unresolved
                   :remediation-hint (df-remediation f))
                  blockers)))))
    (nreverse blockers)))

;;; ─── Bundle Builder ───

(defun %decide-gate (s1-verdict conformance-p drift-ok blockers)
  "Determine gate decision from evidence."
  (declare (type s1-verdict s1-verdict)
           (type boolean conformance-p drift-ok)
           (type list blockers))
  (cond
    ;; Clean pass
    ((and (eq :gate-pass s1-verdict) conformance-p drift-ok (null blockers))
     :pass)
    ;; External blockers present
    ((some (lambda (b)
             (member (be-blocker-class b)
                     '(:external-runtime :transport :auth)))
           blockers)
     :blocked-external)
    ;; Schema/conformance failures
    ((or (not conformance-p) (not drift-ok))
     :fail)
    ;; Everything else
    (t :inconclusive)))

(defun build-evidence-bundle (s1-result conformance-result drift-reports
                              &key (artifact-shas '()))
  "Build complete evidence bundle for S1 gate."
  (declare (type s1-gate-result s1-result)
           (type conformance-check-result conformance-result)
           (type list drift-reports artifact-shas))
  (let* ((blockers (classify-blockers s1-result conformance-result drift-reports))
         (drift-ok (every #'dr-compatible-p drift-reports))
         (decision (%decide-gate
                    (s1-verdict s1-result)
                    (ccr-conformant-p conformance-result)
                    drift-ok
                    blockers)))
    (make-evidence-bundle
     :gate-id (format nil "s1-~A-~D"
                      (string-downcase
                       (symbol-name (s1-profile s1-result)))
                      (get-universal-time))
     :target-profile (s1-profile s1-result)
     :decision decision
     :s1-verdict (s1-verdict s1-result)
     :conformance-summary (ccr-summary conformance-result)
     :drift-compatible-p drift-ok
     :blockers blockers
     :artifact-shas artifact-shas
     :timestamp (get-universal-time)
     :notes (if (null blockers)
                "All gates passed"
                (format nil "~D blocker(s) classified" (length blockers))))))

;;; ─── JSON Serialization ───

(defun evidence-bundle-to-json (bundle)
  "Serialize evidence bundle to deterministic JSON."
  (declare (type evidence-bundle bundle))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"gate_id\":" s)
    (emit-json-string (eb-gate-id bundle) s)
    (write-string ",\"target_profile\":" s)
    (emit-json-string (string-downcase (symbol-name (eb-target-profile bundle))) s)
    (write-string ",\"decision\":" s)
    (emit-json-string (string-downcase (symbol-name (eb-decision bundle))) s)
    (write-string ",\"s1_verdict\":" s)
    (emit-json-string (string-downcase (symbol-name (eb-s1-verdict bundle))) s)
    (write-string ",\"conformance_summary\":" s)
    (emit-json-string (eb-conformance-summary bundle) s)
    (write-string ",\"drift_compatible\":" s)
    (write-string (if (eb-drift-compatible-p bundle) "true" "false") s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (eb-timestamp bundle))
    (write-string ",\"notes\":" s)
    (emit-json-string (eb-notes bundle) s)
    (write-string ",\"blockers\":[" s)
    (let ((first t))
      (dolist (b (eb-blockers bundle))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"class\":" s)
        (emit-json-string (string-downcase (symbol-name (be-blocker-class b))) s)
        (write-string ",\"reason_code\":" s)
        (emit-json-string (be-reason-code b) s)
        (write-string ",\"description\":" s)
        (emit-json-string (be-description b) s)
        (write-string ",\"resolution\":" s)
        (emit-json-string (string-downcase (symbol-name (be-resolution b))) s)
        (write-string ",\"remediation\":" s)
        (emit-json-string (be-remediation-hint b) s)
        (write-string "}" s)))
    (write-string "]," s)
    (write-string "\"artifact_shas\":[" s)
    (let ((first t))
      (dolist (sha (eb-artifact-shas bundle))
        (unless first (write-char #\, s))
        (setf first nil)
        (emit-json-string sha s)))
    (write-string "]}" s)))
