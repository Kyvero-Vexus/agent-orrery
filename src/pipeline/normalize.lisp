;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; normalize.lisp — Typed normalization pipeline for snapshot/event payloads

(in-package #:orrery/pipeline)

(defstruct (normalized-snapshot
             (:constructor make-normalized-snapshot
                 (&key sessions events alerts sync-token)))
  (sessions '() :type list)
  (events '() :type list)
  (alerts '() :type list)
  (sync-token "" :type string))

(declaim (ftype (function ((or integer float string null) &optional fixnum)
                         (values fixnum &optional))
                normalize-timestamp)
         (ftype (function (hash-table) (values orrery/domain:session-record &optional))
                normalize-session-payload)
         (ftype (function (hash-table) (values orrery/domain:event-record &optional))
                normalize-event-payload)
         (ftype (function (hash-table) (values orrery/domain:alert-record &optional))
                normalize-alert-payload)
         (ftype (function (hash-table) (values normalized-snapshot &optional))
                normalize-snapshot-payload))

(defun %field (ht key &optional default)
  (if (hash-table-p ht)
      (multiple-value-bind (v presentp) (gethash key ht)
        (if presentp v default))
      default))

(defun %string (v &optional (default ""))
  (cond
    ((stringp v) v)
    ((symbolp v) (symbol-name v))
    ((null v) default)
    (t (princ-to-string v))))

(defun normalize-timestamp (value &optional (default 0))
  (declare (type fixnum default))
  (cond
    ((integerp value) value)
    ((floatp value) (truncate value))
    ((stringp value) (or (ignore-errors (parse-integer value)) default))
    (t default)))

(defun %kw (value fallback)
  (let* ((s (cond
              ((keywordp value) (symbol-name value))
              ((stringp value) value)
              ((symbolp value) (symbol-name value))
              (t nil)))
         (k (and s (ignore-errors (intern (string-upcase s) :keyword)))))
    (or k fallback)))

(defun normalize-session-payload (obj)
  (orrery/domain:make-session-record
   :id (%string (%field obj "id" ""))
   :agent-name (%string (%field obj "agent" (%field obj "agent_name" "")))
   :channel (%string (%field obj "channel" ""))
   :status (%kw (%field obj "status" :active) :active)
   :model (%string (%field obj "model" ""))
   :created-at (normalize-timestamp (%field obj "created_at" 0))
   :updated-at (normalize-timestamp (%field obj "updated_at" 0))
   :message-count (normalize-timestamp (%field obj "message_count" 0))
   :total-tokens (normalize-timestamp (%field obj "total_tokens" 0))
   :estimated-cost-cents (normalize-timestamp (%field obj "estimated_cost_cents" 0))))

(defun normalize-event-payload (obj)
  (orrery/domain:make-event-record
   :id (%string (%field obj "id" ""))
   :kind (%kw (%field obj "kind" :info) :info)
   :source (%string (%field obj "source" ""))
   :message (%string (%field obj "message" ""))
   :timestamp (normalize-timestamp (%field obj "timestamp" 0))
   :metadata (%field obj "metadata" nil)))

(defun normalize-alert-payload (obj)
  (orrery/domain:make-alert-record
   :id (%string (%field obj "id" ""))
   :severity (%kw (%field obj "severity" :warning) :warning)
   :title (%string (%field obj "title" ""))
   :message (%string (%field obj "message" ""))
   :source (%string (%field obj "source" ""))
   :fired-at (normalize-timestamp (%field obj "fired_at" 0))
   :acknowledged-p (not (null (%field obj "acknowledged" nil)))
   :snoozed-until (let ((v (%field obj "snoozed_until" nil)))
                    (and v (normalize-timestamp v)))))

(defun %vector-or-list->list (x)
  (cond
    ((vectorp x) (coerce x 'list))
    ((listp x) x)
    (t '())))

(defun normalize-snapshot-payload (obj)
  (let* ((sessions (%vector-or-list->list (%field obj "sessions" '())))
         (events (%vector-or-list->list (%field obj "events" '())))
         (alerts (%vector-or-list->list (%field obj "alerts" '()))))
    (make-normalized-snapshot
     :sessions (mapcar #'normalize-session-payload sessions)
     :events (mapcar #'normalize-event-payload events)
     :alerts (mapcar #'normalize-alert-payload alerts)
     :sync-token (%string (%field obj "sync_token" "")))))
