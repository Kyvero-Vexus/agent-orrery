;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; audit-trail-bridge.lisp — CL adapter for Coalton audit trail
;;;
;;; Bead: agent-orrery-vaim

(in-package #:orrery/adapter)

;;; The domain type audit-trail-entry is already defined in
;;; src/domain/types.lisp, so we just provide conversion functions.

(declaim
 (ftype (function (t) (values audit-trail-entry &optional)) coalton-entry->cl)
 (ftype (function (list) (values list &optional)) coalton-entries->cl)
 (ftype (function (audit-trail-entry) (values string &optional)) audit-trail-entry->json)
 (ftype (function (list) (values string &optional)) audit-trail-entries->json))

(defun coalton-entry->cl (coalton-entry)
  "Convert a Coalton AuditEntry to CL audit-trail-entry."
  (declare (optimize (safety 3)))
  (make-audit-trail-entry
   :seq (orrery/coalton/core:cl-entry-seq coalton-entry)
   :timestamp (orrery/coalton/core:cl-entry-timestamp coalton-entry)
   :category (orrery/coalton/core:cl-entry-category-label coalton-entry)
   :severity (orrery/coalton/core:cl-entry-severity-label coalton-entry)
   :actor (orrery/coalton/core:cl-entry-actor coalton-entry)
   :summary (orrery/coalton/core:cl-entry-summary coalton-entry)
   :detail (orrery/coalton/core:cl-entry-detail coalton-entry)
   :hash (orrery/coalton/core:cl-entry-hash coalton-entry)))

(defun coalton-entries->cl (coalton-entries)
  "Convert a list of Coalton AuditEntry to CL audit-trail-entry list."
  (declare (optimize (safety 3)))
  (mapcar #'coalton-entry->cl coalton-entries))

(defun audit-trail-entry->json (entry)
  "Deterministic JSON emitter for a single audit trail entry."
  (declare (type audit-trail-entry entry) (optimize (safety 3)))
  (format nil "{\"seq\":~D,\"timestamp\":~D,\"category\":\"~A\",\"severity\":\"~A\",~
\"actor\":\"~A\",\"summary\":\"~A\",\"detail\":\"~A\",\"hash\":\"~A\"}"
          (ate-seq entry)
          (ate-timestamp entry)
          (ate-category entry)
          (ate-severity entry)
          (ate-actor entry)
          (ate-summary entry)
          (ate-detail entry)
          (ate-hash entry)))

(defun audit-trail-entries->json (entries)
  "Deterministic JSON emitter for a list of audit trail entries."
  (declare (type list entries) (optimize (safety 3)))
  (format nil "[~{~A~^,~}]"
          (mapcar #'audit-trail-entry->json entries)))
