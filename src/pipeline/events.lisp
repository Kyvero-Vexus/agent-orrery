;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; events.lisp — Event ingest and projection pipeline
;;;

(in-package #:orrery/pipeline)

(defstruct (projection-state (:conc-name ps-))
  "Functional projection state derived from adapter events."
  (usage (make-hash-table :test 'equal) :type hash-table)
  (activity '() :type list)
  (alerts (make-hash-table :test 'equal) :type hash-table))

(declaim (ftype (function (projection-state event-record) projection-state) reduce-event))
(defun reduce-event (state event)
  "Reduce EVENT into STATE and return STATE (functional-style API on mutable container)."
  ;; activity feed (latest first)
  (push event (ps-activity state))

  ;; usage projection from metadata (:model, :tokens)
  (let* ((meta (er-metadata event))
         (model (getf meta :model))
         (tokens (getf meta :tokens)))
    (when (and model (integerp tokens) (>= tokens 0))
      (let* ((key (string-downcase (princ-to-string model)))
             (prev (gethash key (ps-usage state) 0))
             (next (+ prev tokens)))
        (setf (gethash key (ps-usage state)) next))))

  ;; alert projection from event kind/source/message
  (when (member (er-kind event) '(:warning :error) :test #'eq)
    (let* ((id (format nil "evt-alert-~A" (er-timestamp event)))
           (sev (if (eq (er-kind event) :error) :critical :warning)))
      (setf (gethash id (ps-alerts state))
            (make-alert-record
             :id id
             :severity sev
             :title (string-capitalize (symbol-name (er-kind event)))
             :message (er-message event)
             :source (er-source event)
             :fired-at (er-timestamp event)
             :acknowledged-p nil
             :snoozed-until nil))))

  state)

(declaim (ftype (function (list &key (:initial-state (or null projection-state))) projection-state)
                ingest-events))
(defun ingest-events (events &key (initial-state nil))
  "Ingest EVENTS into a projection state."
  (let ((state (or initial-state (make-projection-state))))
    (dolist (ev events state)
      (reduce-event state ev))))

(declaim (ftype (function (projection-state) list) project-usage-summary))
(defun project-usage-summary (state)
  "Return usage projection as list of usage-record, one per model."
  (let ((result '())
        (now (get-universal-time)))
    (maphash (lambda (model tokens)
               (push (make-usage-record
                      :model model
                      :period :hourly
                      :timestamp now
                      :prompt-tokens (floor tokens 2)
                      :completion-tokens (- tokens (floor tokens 2))
                      :total-tokens tokens
                      :estimated-cost-cents (estimate-cost-cents tokens))
                     result))
             (ps-usage state))
    (nreverse result)))

(declaim (ftype (function (projection-state &key (:limit fixnum)) list) project-activity-feed))
(defun project-activity-feed (state &key (limit 50))
  "Return the latest activity events, limited to LIMIT."
  (subseq (ps-activity state) 0 (min limit (length (ps-activity state)))))

(declaim (ftype (function (projection-state) list) project-alert-state))
(defun project-alert-state (state)
  "Return projected alerts as list of alert-record."
  (let ((result '()))
    (maphash (lambda (_id alert)
               (declare (ignore _id))
               (push alert result))
             (ps-alerts state))
    (nreverse result)))
