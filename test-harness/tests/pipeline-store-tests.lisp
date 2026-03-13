;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; pipeline-store-tests.lisp — Event pipeline + sync store tests
;;;

(in-package #:orrery/harness-tests)

(define-test pipeline-store-tests)

(define-test (pipeline-store-tests ingest-and-project)
  (let* ((events (list (make-event-record :id "e1" :kind :info :source "system"
                                          :message "ok" :timestamp 100
                                          :metadata '(:model "gpt-4" :tokens 300))
                       (make-event-record :id "e2" :kind :warning :source "system"
                                          :message "warn" :timestamp 200
                                          :metadata '(:model "gpt-4" :tokens 200))))
         (st (orrery/pipeline:ingest-events events))
         (usage (orrery/pipeline:project-usage-summary st))
         (activity (orrery/pipeline:project-activity-feed st :limit 10))
         (alerts (orrery/pipeline:project-alert-state st)))
    (is = 1 (length usage))
    (is = 500 (ur-total-tokens (first usage)))
    (is = 2 (length activity))
    (is = 1 (length alerts))
    (is eq :warning (ar-severity (first alerts)))))

(define-test (pipeline-store-tests snapshot-and-incremental-sync)
  (let* ((adapter (make-fixture-adapter))
         (store (orrery/store:snapshot-from-adapter adapter :sync-token "t0"))
         (new-events (list (make-event-record :id "inc1" :kind :info :source "system"
                                              :message "delta" :timestamp 777
                                              :metadata '(:model "claude-3" :tokens 250)))))
    (is string= "t0" (orrery/store:ss-sync-token store))
    (true (plusp (length (orrery/store:ss-sessions store))))
    (orrery/store:apply-incremental-events store new-events :sync-token "t1")
    (is string= "t1" (orrery/store:ss-sync-token store))
    (true (find "inc1" (orrery/store:ss-events store) :key #'er-id :test #'string=))
    (true (plusp (length (orrery/store:ss-usage store))))
    (true (listp (orrery/store:store->plist store)))))
