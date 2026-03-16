;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; ui-protocol-boundary.lisp — Typed UI protocol boundary for TUI/Web drivers
;;; Bead: agent-orrery-sdk

(in-package #:orrery/adapter)

(deftype ui-surface () '(member :tui :web))
(deftype ui-message-kind () '(member :session :cron :health :alert :audit :analytics :capacity :cost :status))
(deftype ui-error-kind () '(member :transport :validation :not-found :not-supported :internal))

(defstruct (ui-message (:conc-name uim-))
  (id "" :type string)
  (surface :tui :type ui-surface)
  (kind :status :type ui-message-kind)
  (payload nil :type list)
  (timestamp 0 :type integer)
  (sequence 0 :type fixnum)
  (deterministic-key "" :type string))

(defstruct (ui-contract (:conc-name uic-))
  (surface :tui :type ui-surface)
  (kind :status :type ui-message-kind)
  (required-fields nil :type list)
  (schema-version "1.0" :type string))

(defstruct (ui-error-adt (:conc-name uie-))
  (kind :internal :type ui-error-kind)
  (code "ERR_INTERNAL" :type string)
  (message "" :type string)
  (recoverable-p nil :type boolean)
  (details nil :type list))

(defstruct (ui-replay-hook (:conc-name urh-))
  (hook-id "" :type string)
  (surface :tui :type ui-surface)
  (deterministic-command "" :type string)
  (artifact-dir "" :type string)
  (seed 0 :type fixnum)
  (enabled-p t :type boolean))

(declaim
 (ftype (function (ui-surface ui-message-kind integer fixnum) (values string &optional)) make-ui-message-id)
 (ftype (function (ui-surface ui-message-kind integer fixnum list) (values ui-message &optional)) make-ui-message*)
 (ftype (function (ui-message ui-contract) (values list &optional)) validate-ui-message)
 (ftype (function (keyword string string &optional list) (values ui-error-adt &optional)) project-ui-error)
 (ftype (function (ui-message) (values string &optional)) ui-message->json)
 (ftype (function (ui-contract) (values string &optional)) ui-contract->json)
 (ftype (function (ui-error-adt) (values string &optional)) ui-error->json)
 (ftype (function (ui-replay-hook) (values string &optional)) ui-replay-hook->json))

(defun make-ui-message-id (surface kind timestamp sequence)
  (declare (type ui-surface surface)
           (type ui-message-kind kind)
           (type integer timestamp)
           (type fixnum sequence))
  (format nil "~(~A~)-~(~A~)-~D-~D" surface kind timestamp sequence))

(defun make-ui-message* (surface kind timestamp sequence payload)
  (declare (type ui-surface surface)
           (type ui-message-kind kind)
           (type integer timestamp)
           (type fixnum sequence)
           (type list payload))
  (let ((id (make-ui-message-id surface kind timestamp sequence)))
    (make-ui-message
     :id id
     :surface surface
     :kind kind
     :payload payload
     :timestamp timestamp
     :sequence sequence
     :deterministic-key id)))

(defun validate-ui-message (message contract)
  "Return list of validation error strings. Empty list means valid." 
  (declare (type ui-message message) (type ui-contract contract))
  (let ((errors nil))
    (unless (eq (uim-surface message) (uic-surface contract))
      (push "surface-mismatch" errors))
    (unless (eq (uim-kind message) (uic-kind contract))
      (push "kind-mismatch" errors))
    (dolist (field (uic-required-fields contract))
      (unless (assoc field (uim-payload message) :test #'eq)
        (push (format nil "missing-field:~A" field) errors)))
    (nreverse errors)))

(defun project-ui-error (kind code message &optional (details nil))
  (declare (type ui-error-kind kind)
           (type string code message)
           (type list details))
  (make-ui-error-adt
   :kind kind
   :code code
   :message message
   :recoverable-p (not (null (member kind '(:transport :validation :not-supported) :test #'eq)))
   :details details))

(defun ui-message->json (message)
  (declare (type ui-message message))
  (format nil
          "{\"id\":\"~A\",\"surface\":\"~A\",\"kind\":\"~A\",\"timestamp\":~D,\"sequence\":~D,\"deterministic_key\":\"~A\"}"
          (uim-id message)
          (string-downcase (symbol-name (uim-surface message)))
          (string-downcase (symbol-name (uim-kind message)))
          (uim-timestamp message)
          (uim-sequence message)
          (uim-deterministic-key message)))

(defun ui-contract->json (contract)
  (declare (type ui-contract contract))
  (format nil
          "{\"surface\":\"~A\",\"kind\":\"~A\",\"schema\":\"~A\",\"required_fields\":[~{\"~A\"~^,~}]}"
          (string-downcase (symbol-name (uic-surface contract)))
          (string-downcase (symbol-name (uic-kind contract)))
          (uic-schema-version contract)
          (mapcar (lambda (x) (string-downcase (symbol-name x)))
                  (uic-required-fields contract))))

(defun ui-error->json (err)
  (declare (type ui-error-adt err))
  (format nil
          "{\"kind\":\"~A\",\"code\":\"~A\",\"message\":\"~A\",\"recoverable\":~A}"
          (string-downcase (symbol-name (uie-kind err)))
          (uie-code err)
          (uie-message err)
          (if (uie-recoverable-p err) "true" "false")))

(defun ui-replay-hook->json (hook)
  (declare (type ui-replay-hook hook))
  (format nil
          "{\"hook_id\":\"~A\",\"surface\":\"~A\",\"command\":\"~A\",\"artifact_dir\":\"~A\",\"seed\":~D,\"enabled\":~A}"
          (urh-hook-id hook)
          (string-downcase (symbol-name (urh-surface hook)))
          (urh-deterministic-command hook)
          (urh-artifact-dir hook)
          (urh-seed hook)
          (if (urh-enabled-p hook) "true" "false")))
