;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; sdk.lisp — Plugin SDK: typed extension points for cards, commands, transformers
;;; Bead: agent-orrery-eb0.6.1

(in-package #:orrery/plugin)

;;; ─── Card Definition ───

(defstruct (card-definition (:conc-name cd-))
  "Defines a dashboard card extension."
  (name     "" :type string)
  (title    "" :type string)
  (renderer nil :type (or null function))  ; (lambda (data stream) ...)
  (data-fn  nil :type (or null function))  ; (lambda () -> data)
  (priority 50 :type fixnum))

;;; ─── Command Definition ───

(defstruct (command-definition (:conc-name cmd-))
  "Defines a command extension."
  (name        "" :type string)
  (handler     nil :type (or null function))  ; (lambda (&rest args) ...)
  (description "" :type string)
  (keystroke   nil :type (or null character)))

;;; ─── Transformer Definition ───

(defstruct (transformer-definition (:conc-name td-))
  "Defines a data transformer extension."
  (name        "" :type string)
  (input-type  :any :type keyword)
  (output-type :any :type keyword)
  (transform-fn nil :type (or null function)))  ; (lambda (input) -> output)

;;; ─── Plugin Protocol (CLOS) ───

(defclass plugin ()
  ((name        :initarg :name        :reader plugin-name
                :type string :initform "")
   (version     :initarg :version     :reader plugin-version
                :type string :initform "0.0.0")
   (description :initarg :description :reader plugin-description
                :type string :initform ""))
  (:documentation "Base class for Agent Orrery plugins."))

(defgeneric plugin-card-definitions (plugin)
  (:documentation "Return list of card-definition structs this plugin provides.")
  (:method ((p plugin)) nil))

(defgeneric plugin-command-definitions (plugin)
  (:documentation "Return list of command-definition structs this plugin provides.")
  (:method ((p plugin)) nil))

(defgeneric plugin-transformer-definitions (plugin)
  (:documentation "Return list of transformer-definition structs this plugin provides.")
  (:method ((p plugin)) nil))

;;; ─── Registry ───

(defvar *plugin-registry* (make-hash-table :test #'equal)
  "Registry mapping plugin names to plugin instances.")

(declaim (ftype (function (plugin) (values plugin &optional)) register-plugin))
(defun register-plugin (plugin)
  "Register a plugin in the global registry."
  (setf (gethash (plugin-name plugin) *plugin-registry*) plugin)
  plugin)

(declaim (ftype (function (string) (values null &optional)) unregister-plugin))
(defun unregister-plugin (name)
  "Remove a plugin from the registry."
  (remhash name *plugin-registry*)
  nil)

(declaim (ftype (function (string) (values (or null plugin) &optional)) find-plugin))
(defun find-plugin (name)
  "Find a plugin by name."
  (nth-value 0 (gethash name *plugin-registry*)))

(declaim (ftype (function () (values list &optional)) list-plugins))
(defun list-plugins ()
  "List all registered plugins."
  (let ((plugins nil))
    (maphash (lambda (k v) (declare (ignore k)) (push v plugins)) *plugin-registry*)
    (nreverse plugins)))

;;; ─── Aggregation ───

(declaim (ftype (function () (values list &optional)) all-card-definitions))
(defun all-card-definitions ()
  "Collect all card definitions from all registered plugins."
  (let ((cards nil))
    (maphash (lambda (k v) (declare (ignore k))
               (setf cards (append cards (plugin-card-definitions v))))
             *plugin-registry*)
    (sort (copy-list cards) #'< :key #'cd-priority)))

(declaim (ftype (function () (values list &optional)) all-command-definitions))
(defun all-command-definitions ()
  "Collect all command definitions from all registered plugins."
  (let ((cmds nil))
    (maphash (lambda (k v) (declare (ignore k))
               (setf cmds (append cmds (plugin-command-definitions v))))
             *plugin-registry*)
    cmds))

(declaim (ftype (function () (values list &optional)) all-transformer-definitions))
(defun all-transformer-definitions ()
  "Collect all transformer definitions from all registered plugins."
  (let ((xfs nil))
    (maphash (lambda (k v) (declare (ignore k))
               (setf xfs (append xfs (plugin-transformer-definitions v))))
             *plugin-registry*)
    xfs))

;;; ─── Validation ───

(defstruct (plugin-validation-result (:conc-name pvr-))
  "Result of validating a plugin."
  (valid-p t :type boolean)
  (errors nil :type list)
  (warnings nil :type list))

;;; ─── v2 Lifecycle Hooks (a3p) ───

(deftype hook-phase ()
  '(member :before :after :error))

(defstruct (lifecycle-hook (:conc-name lh-))
  "A typed lifecycle hook for v2 Coalton module events."
  (name     "" :type string)
  (module   :core :type keyword)
  (phase    :after :type hook-phase)
  (handler  nil :type (or null function))
  (priority 50 :type fixnum))

(defgeneric plugin-lifecycle-hooks (plugin)
  (:documentation "Return list of lifecycle-hook structs for v2 module events.
Supported modules: :audit-trail, :cost-optimizer, :capacity-planner,
:session-analytics, :scenario-planning.")
  (:method ((p plugin)) nil))

(defgeneric plugin-on-audit-event (plugin entry)
  (:documentation "Called when a new audit trail entry is created.")
  (:method ((p plugin) entry) (declare (ignore entry)) nil))

(defgeneric plugin-on-cost-recommendation (plugin recommendation)
  (:documentation "Called when cost optimizer produces a recommendation.")
  (:method ((p plugin) recommendation) (declare (ignore recommendation)) nil))

(defgeneric plugin-on-capacity-assessment (plugin plan)
  (:documentation "Called when capacity planner produces an assessment.")
  (:method ((p plugin) plan) (declare (ignore plan)) nil))

(defgeneric plugin-on-session-analytics (plugin summary)
  (:documentation "Called when session analytics summary is computed.")
  (:method ((p plugin) summary) (declare (ignore summary)) nil))

(defgeneric plugin-on-scenario-projection (plugin result)
  (:documentation "Called when a scenario projection completes.")
  (:method ((p plugin) result) (declare (ignore result)) nil))

;;; v2 extended hooks (bead tm00)

(defgeneric plugin-on-anomaly-detection (plugin anomaly)
  (:documentation "Called when the anomaly-detector module identifies an anomaly.")
  (:method ((p plugin) anomaly) (declare (ignore anomaly)) nil))

(defgeneric plugin-on-notification-routed (plugin notification)
  (:documentation "Called when a notification is routed by the notification-routing module.")
  (:method ((p plugin) notification) (declare (ignore notification)) nil))

(defun dispatch-lifecycle-hooks (plugin module phase data)
  "Dispatch lifecycle hooks for MODULE at PHASE with DATA.
Returns list of (hook-name . result) pairs."
  (declare (type plugin plugin) (type keyword module phase) (optimize (safety 3)))
  (let ((results nil))
    (dolist (hook (plugin-lifecycle-hooks plugin))
      (when (and (eq (lh-module hook) module)
                 (eq (lh-phase hook) phase)
                 (lh-handler hook))
        (handler-case
            (let ((result (funcall (lh-handler hook) data)))
              (push (cons (lh-name hook) result) results))
          (error (c)
            (push (cons (lh-name hook) (format nil "ERROR: ~A" c)) results)))))
    (nreverse results)))

;;; ─── Validation ───

(declaim (ftype (function (plugin) (values plugin-validation-result &optional))
                validate-plugin))
(defun validate-plugin (plugin)
  "Validate a plugin for required fields and well-formedness."
  (let ((errors nil)
        (warnings nil))
    ;; Name required
    (when (or (null (plugin-name plugin))
              (string= "" (plugin-name plugin)))
      (push "Plugin name is required" errors))
    ;; Version format check
    (when (string= "" (plugin-version plugin))
      (push "Plugin version is empty" warnings))
    ;; Card definitions have renderers
    (dolist (card (plugin-card-definitions plugin))
      (when (null (cd-renderer card))
        (push (format nil "Card ~A has no renderer" (cd-name card)) warnings)))
    ;; Command definitions have handlers
    (dolist (cmd (plugin-command-definitions plugin))
      (when (null (cmd-handler cmd))
        (push (format nil "Command ~A has no handler" (cmd-name cmd)) errors)))
    ;; Transformer definitions have transform functions
    (dolist (xf (plugin-transformer-definitions plugin))
      (when (null (td-transform-fn xf))
        (push (format nil "Transformer ~A has no transform-fn" (td-name xf)) errors)))
    (make-plugin-validation-result
     :valid-p (null errors)
     :errors (nreverse errors)
     :warnings (nreverse warnings))))
