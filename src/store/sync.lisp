;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; sync.lisp — Snapshot + incremental sync store
;;;

(in-package #:orrery/store)

(defstruct (sync-store (:conc-name ss-))
  "Consistent snapshot + incremental state container for UI consumers."
  (sessions '() :type list)
  (cron-jobs '() :type list)
  (health '() :type list)
  (usage '() :type list)
  (events '() :type list)
  (alerts '() :type list)
  (subagents '() :type list)
  (last-sync-at 0 :type fixnum)
  (sync-token nil :type (or null string)))

(declaim (ftype (function (t &key (:sync-token (or null string))) sync-store)
                snapshot-from-adapter))
(defun snapshot-from-adapter (adapter &key (sync-token nil))
  "Build a full snapshot from ADAPTER read surfaces."
  (make-sync-store
   :sessions (adapter-list-sessions adapter)
   :cron-jobs (adapter-list-cron-jobs adapter)
   :health (adapter-system-health adapter)
   :usage (adapter-usage-records adapter :period :hourly)
   :events (adapter-tail-events adapter :since 0 :limit 500)
   :alerts (adapter-list-alerts adapter)
   :subagents (adapter-list-subagents adapter)
   :last-sync-at (get-universal-time)
   :sync-token sync-token))

(declaim (ftype (function (sync-store list &key (:sync-token (or null string))) sync-store)
                apply-incremental-events))
(defun apply-incremental-events (store new-events &key (sync-token nil))
  "Apply NEW-EVENTS into STORE and refresh derived projections."
  (let* ((all-events (append (ss-events store) new-events))
         (state (ingest-events all-events)))
    (setf (ss-events store) all-events)
    (setf (ss-usage store) (project-usage-summary state))
    (setf (ss-alerts store) (project-alert-state state))
    (setf (ss-last-sync-at store) (get-universal-time))
    (when sync-token
      (setf (ss-sync-token store) sync-token))
    store))

(declaim (ftype (function (sync-store list) sync-store) replay-events))
(defun replay-events (store events)
  "Replay EVENTS into STORE from scratch-derived projections."
  (setf (ss-events store) '())
  (apply-incremental-events store events))

(declaim (ftype (function (sync-store) list) store->plist))
(defun store->plist (store)
  "Serialize STORE into a plist-friendly shape."
  (list :sessions (ss-sessions store)
        :cron-jobs (ss-cron-jobs store)
        :health (ss-health store)
        :usage (ss-usage store)
        :events (ss-events store)
        :alerts (ss-alerts store)
        :subagents (ss-subagents store)
        :last-sync-at (ss-last-sync-at store)
        :sync-token (ss-sync-token store)))
