;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capability-contract.lisp — Typed adapter capability contract + negotiation
;;;
;;; Provides:
;;; 1. Capability schema — declares what an adapter can do
;;; 2. Schema validators — structural + semantic validation
;;; 3. Negotiation flow — selects safe execution paths from declared caps

(in-package #:orrery/adapter)

;;; ─── Capability Schema ───

(deftype capability-version ()
  '(member :v1 :v2))

(deftype endpoint-semantic ()
  '(member :read-only :read-write :destructive :administrative))

(defstruct (capability-schema
             (:constructor make-capability-schema
                 (&key adapter-name adapter-version protocol-version
                       endpoints semantic-map metadata))
             (:conc-name cs-))
  "Declares the full capability surface of an adapter."
  (adapter-name "" :type string)
  (adapter-version "0.0.0" :type string)
  (protocol-version :v1 :type capability-version)
  (endpoints '() :type list)      ; list of endpoint-capability
  (semantic-map '() :type list)   ; alist (string . endpoint-semantic)
  (metadata '() :type list))      ; alist for extensibility

(defstruct (endpoint-capability
             (:constructor make-endpoint-capability
                 (&key path operation semantic supported-p requires-auth))
             (:conc-name ec-cap-))
  "Declares one endpoint's capability."
  (path "" :type string)
  (operation :read :type keyword)
  (semantic :read-only :type endpoint-semantic)
  (supported-p t :type boolean)
  (requires-auth nil :type boolean))

;;; ─── Validation Result ───

(deftype validation-severity ()
  '(member :error :warning :info))

(defstruct (validation-issue
             (:constructor make-validation-issue (&key severity field message))
             (:conc-name vi-))
  (severity :error :type validation-severity)
  (field "" :type string)
  (message "" :type string))

(defstruct (validation-result
             (:constructor make-validation-result (&key valid-p issues))
             (:conc-name vr-))
  (valid-p t :type boolean)
  (issues '() :type list))

;;; ─── Schema Validators ───

(declaim (ftype (function (capability-schema) (values validation-result &optional))
                validate-schema)
         (ftype (function (endpoint-capability) (values list &optional))
                validate-endpoint-capability))

(defun validate-endpoint-capability (ec)
  "Validate a single endpoint capability. Returns list of issues."
  (declare (type endpoint-capability ec))
  (let ((issues '()))
    (when (string= "" (ec-cap-path ec))
      (push (make-validation-issue
             :severity :error :field "path"
             :message "Endpoint path must be non-empty")
            issues))
    (unless (member (ec-cap-semantic ec) '(:read-only :read-write :destructive :administrative))
      (push (make-validation-issue
             :severity :error :field "semantic"
             :message (format nil "Invalid semantic: ~A" (ec-cap-semantic ec)))
            issues))
    (when (and (member (ec-cap-semantic ec) '(:destructive :administrative))
               (not (ec-cap-requires-auth ec)))
      (push (make-validation-issue
             :severity :warning :field "requires-auth"
             :message (format nil "~A operations should require auth"
                              (ec-cap-semantic ec)))
            issues))
    (nreverse issues)))

(defun validate-schema (schema)
  "Validate a complete capability schema. Returns validation-result."
  (declare (type capability-schema schema))
  (let ((issues '()))
    ;; Schema-level checks
    (when (string= "" (cs-adapter-name schema))
      (push (make-validation-issue
             :severity :error :field "adapter-name"
             :message "Adapter name must be non-empty")
            issues))
    (when (null (cs-endpoints schema))
      (push (make-validation-issue
             :severity :warning :field "endpoints"
             :message "Schema declares no endpoints")
            issues))
    ;; Validate each endpoint
    (dolist (ep (cs-endpoints schema))
      (dolist (issue (validate-endpoint-capability ep))
        (push issue issues)))
    ;; Check for duplicate paths
    (let ((paths (mapcar #'ec-cap-path (cs-endpoints schema))))
      (when (> (length paths) (length (remove-duplicates paths :test #'string=)))
        (push (make-validation-issue
               :severity :warning :field "endpoints"
               :message "Duplicate endpoint paths detected")
              issues)))
    (let ((errors (remove-if-not (lambda (i) (eq :error (vi-severity i))) issues)))
      (make-validation-result
       :valid-p (null errors)
       :issues (nreverse issues)))))

;;; ─── Negotiation Flow ───

(deftype negotiation-outcome ()
  '(member :full-access :partial-access :read-only :no-access))

(defstruct (negotiation-result
             (:constructor make-negotiation-result
                 (&key outcome available-operations
                       denied-operations requires-elevation
                       diagnostics))
             (:conc-name nr-))
  "Result of capability negotiation between pipeline and adapter."
  (outcome :no-access :type negotiation-outcome)
  (available-operations '() :type list)
  (denied-operations '() :type list)
  (requires-elevation '() :type list)
  (diagnostics '() :type list))

(declaim (ftype (function (capability-schema list) (values negotiation-result &optional))
                negotiate-capabilities))

(defun negotiate-capabilities (schema requested-ops)
  "Negotiate adapter capabilities against requested operations.
   REQUESTED-OPS is a list of operation keywords the pipeline wants.
   Returns negotiation-result with outcome and per-op breakdown."
  (declare (type capability-schema schema) (type list requested-ops))
  (let ((available '())
        (denied '())
        (elevation '()))
    (dolist (op requested-ops)
      (let ((ep (find op (cs-endpoints schema)
                      :key #'ec-cap-operation :test #'eq)))
        (cond
          ((null ep) (push op denied))
          ((not (ec-cap-supported-p ep)) (push op denied))
          ((and (ec-cap-requires-auth ep)
                (member (ec-cap-semantic ep) '(:destructive :administrative)))
           (push op elevation)
           (push op available))
          (t (push op available)))))
    (let* ((avail-count (length available))
           (total (length requested-ops))
           (outcome (cond
                      ((zerop total) :no-access)
                      ((= avail-count total) :full-access)
                      ((zerop avail-count) :no-access)
                      ((every (lambda (ep)
                                (member (ec-cap-semantic ep) '(:read-only)))
                              (remove-if-not #'ec-cap-supported-p
                                             (cs-endpoints schema)))
                       :read-only)
                      (t :partial-access))))
      (make-negotiation-result
       :outcome outcome
       :available-operations (nreverse available)
       :denied-operations (nreverse denied)
       :requires-elevation (nreverse elevation)
       :diagnostics (list (format nil "~D/~D operations available" avail-count total))))))
