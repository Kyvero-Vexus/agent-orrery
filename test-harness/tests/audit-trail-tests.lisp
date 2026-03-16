;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; audit-trail-tests.lisp — Tests for Coalton audit trail with hash chain
;;;
;;; Bead: agent-orrery-8cn

(in-package #:orrery/harness-tests)

;;; ============================================================
;;; Audit Trail Tests
;;; ============================================================

(define-test audit-trail-tests)

;;; --- Deterministic test hash function ---

(cl:defun %test-hash-fn (input)
  "Deterministic stub: SHA-256 of input via ironclad if available,
   otherwise a simple string hash for testing."
  (cl:declare (cl:type cl:string input))
  (cl:let* ((digest (ironclad:digest-sequence
                     :sha256
                     (babel:string-to-octets input :encoding :utf-8)))
            (hex (ironclad:byte-array-to-hex-string digest)))
    hex))

(cl:defun %coalton-test-hash-fn ()
  "Return a Coalton-callable hash function wrapping %test-hash-fn."
  (cl:lambda (input)
    (coalton:coalton
     (orrery/coalton/core:AuditHash
      (coalton:lisp coalton:String ()
        (%test-hash-fn input))))))

;;; --- Empty trail ---

(define-test (audit-trail-tests empty-trail)
  (let ((trail (orrery/coalton/core:cl-empty-trail)))
    (true trail)
    (is = 0 (orrery/coalton/core:cl-trail-count trail))
    (is string= "0000000000000000000000000000000000000000000000000000000000000000"
        (orrery/coalton/core:cl-trail-tip-hash trail))))

;;; --- Category labels ---

(define-test (audit-trail-tests category-labels)
  (is string= "session-lifecycle"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditSessionLifecycle)))
  (is string= "cron-execution"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditCronExecution)))
  (is string= "policy-change"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditPolicyChange)))
  (is string= "config-change"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditConfigChange)))
  (is string= "alert-fired"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditAlertFired)))
  (is string= "gate-decision"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditGateDecision)))
  (is string= "model-routing"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditModelRouting)))
  (is string= "adapter-event"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditAdapterEvent)))
  (is string= "manual-action"
      (coalton:coalton (orrery/coalton/core:audit-category-label
                        orrery/coalton/core:AuditManualAction))))

;;; --- Severity labels and scores ---

(define-test (audit-trail-tests severity-labels)
  (is string= "trace"
      (coalton:coalton (orrery/coalton/core:audit-severity-label
                        orrery/coalton/core:AuditTrace)))
  (is string= "info"
      (coalton:coalton (orrery/coalton/core:audit-severity-label
                        orrery/coalton/core:AuditInfo)))
  (is string= "warning"
      (coalton:coalton (orrery/coalton/core:audit-severity-label
                        orrery/coalton/core:AuditWarning)))
  (is string= "critical"
      (coalton:coalton (orrery/coalton/core:audit-severity-label
                        orrery/coalton/core:AuditCritical))))

(define-test (audit-trail-tests severity-scores)
  (is = 0 (coalton:coalton (orrery/coalton/core:audit-severity-score
                             orrery/coalton/core:AuditTrace)))
  (is = 1 (coalton:coalton (orrery/coalton/core:audit-severity-score
                             orrery/coalton/core:AuditInfo)))
  (is = 2 (coalton:coalton (orrery/coalton/core:audit-severity-score
                             orrery/coalton/core:AuditWarning)))
  (is = 3 (coalton:coalton (orrery/coalton/core:audit-severity-score
                             orrery/coalton/core:AuditCritical))))

;;; --- Single entry append ---

(define-test (audit-trail-tests single-append)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (trail2 (orrery/coalton/core:cl-append-entry
                  #'%test-hash-fn trail
                  1000 (orrery/coalton/core:cl-audit-session-lifecycle)
                  (orrery/coalton/core:cl-audit-info)
                  "gensym" "Session created" "{\"id\":\"s1\"}")))
    (is = 1 (orrery/coalton/core:cl-trail-count trail2))
    ;; Tip hash should have changed
    (false (string= (orrery/coalton/core:cl-trail-tip-hash trail)
                     (orrery/coalton/core:cl-trail-tip-hash trail2)))))

;;; --- Entry accessors ---

(define-test (audit-trail-tests entry-accessors)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (entry (orrery/coalton/core:cl-make-single-entry
                 #'%test-hash-fn trail
                 42 (orrery/coalton/core:cl-audit-cron-execution)
                 (orrery/coalton/core:cl-audit-warning)
                 "cron-driver" "Job failed" "{\"job\":\"sync\"}")))
    (true entry)
    (is = 0 (orrery/coalton/core:cl-entry-seq entry))
    (is = 42 (orrery/coalton/core:cl-entry-timestamp entry))
    (is string= "cron-execution" (orrery/coalton/core:cl-entry-category-label entry))
    (is string= "warning" (orrery/coalton/core:cl-entry-severity-label entry))
    (is string= "cron-driver" (orrery/coalton/core:cl-entry-actor entry))
    (is string= "Job failed" (orrery/coalton/core:cl-entry-summary entry))
    (is string= "{\"job\":\"sync\"}" (orrery/coalton/core:cl-entry-detail entry))
    ;; Hash should be non-empty
    (true (plusp (length (orrery/coalton/core:cl-entry-hash entry))))
    ;; Prev hash should be genesis
    (is string= "0000000000000000000000000000000000000000000000000000000000000000"
        (orrery/coalton/core:cl-entry-prev-hash entry))))

;;; --- Multi-entry chain ---

(define-test (audit-trail-tests multi-entry-chain)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (t1 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn trail
              100 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-info)
              "agent-a" "Start" "{}"))
         (t2 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t1
              200 (orrery/coalton/core:cl-audit-model-routing)
              (orrery/coalton/core:cl-audit-trace)
              "agent-a" "Routed to opus" "{\"model\":\"opus\"}"))
         (t3 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t2
              300 (orrery/coalton/core:cl-audit-gate-decision)
              (orrery/coalton/core:cl-audit-critical)
              "gate-runner" "Gate FAIL" "{\"verdict\":\"fail\"}")))
    (is = 3 (orrery/coalton/core:cl-trail-count t3))
    ;; Each append produces a different tip
    (false (string= (orrery/coalton/core:cl-trail-tip-hash t1)
                     (orrery/coalton/core:cl-trail-tip-hash t2)))
    (false (string= (orrery/coalton/core:cl-trail-tip-hash t2)
                     (orrery/coalton/core:cl-trail-tip-hash t3)))))

;;; --- Chain verification ---

(define-test (audit-trail-tests verify-valid-chain)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (t1 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn trail
              100 (orrery/coalton/core:cl-audit-config-change)
              (orrery/coalton/core:cl-audit-info)
              "admin" "Config updated" "{}"))
         (t2 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t1
              200 (orrery/coalton/core:cl-audit-alert-fired)
              (orrery/coalton/core:cl-audit-warning)
              "monitor" "Budget warning" "{\"pct\":85}"))
         (t3 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t2
              300 (orrery/coalton/core:cl-audit-manual-action)
              (orrery/coalton/core:cl-audit-info)
              "human" "Acknowledged alert" "{}")))
    ;; Valid chain should verify
    (true (orrery/coalton/core:cl-verify-trail #'%test-hash-fn t3))))

(define-test (audit-trail-tests verify-empty-trail)
  "Empty trail is trivially valid."
  (let ((trail (orrery/coalton/core:cl-empty-trail)))
    (true (orrery/coalton/core:cl-verify-trail #'%test-hash-fn trail))))

(define-test (audit-trail-tests verify-single-entry)
  "Single-entry trail verifies correctly."
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (t1 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn trail
              999 (orrery/coalton/core:cl-audit-adapter-event)
              (orrery/coalton/core:cl-audit-trace)
              "adapter" "Connected" "{}")))
    (true (orrery/coalton/core:cl-verify-trail #'%test-hash-fn t1))))

;;; --- Filter by category ---

(define-test (audit-trail-tests filter-by-category)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (t1 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn trail
              100 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-info)
              "a" "s1" "{}"))
         (t2 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t1
              200 (orrery/coalton/core:cl-audit-cron-execution)
              (orrery/coalton/core:cl-audit-info)
              "b" "c1" "{}"))
         (t3 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t2
              300 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-warning)
              "a" "s2" "{}")))
    ;; Should find 2 session-lifecycle entries
    (let ((results (orrery/coalton/core:cl-filter-by-category
                    (orrery/coalton/core:cl-audit-session-lifecycle) t3)))
      (is = 2 (coalton:coalton (coalton-prelude:length (coalton:lisp (coalton:List orrery/coalton/core:AuditEntry) () results)))))))

;;; --- Filter by severity minimum ---

(define-test (audit-trail-tests filter-by-severity-min)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (t1 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn trail
              100 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-trace)
              "a" "trace" "{}"))
         (t2 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t1
              200 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-info)
              "b" "info" "{}"))
         (t3 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t2
              300 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-warning)
              "c" "warning" "{}"))
         (t4 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t3
              400 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-critical)
              "d" "critical" "{}")))
    ;; Filter >= warning should return 2 entries
    (let ((results (orrery/coalton/core:cl-filter-by-severity-min
                    (orrery/coalton/core:cl-audit-warning) t4)))
      (is = 2 (coalton:coalton (coalton-prelude:length (coalton:lisp (coalton:List orrery/coalton/core:AuditEntry) () results)))))))

;;; --- Count by severity ---

(define-test (audit-trail-tests count-by-severity)
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (t1 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn trail
              100 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-info)
              "a" "i1" "{}"))
         (t2 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t1
              200 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-info)
              "b" "i2" "{}"))
         (t3 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn t2
              300 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-warning)
              "c" "w1" "{}")))
    (is = 2 (orrery/coalton/core:cl-count-by-severity
             (orrery/coalton/core:cl-audit-info) t3))
    (is = 1 (orrery/coalton/core:cl-count-by-severity
             (orrery/coalton/core:cl-audit-warning) t3))
    (is = 0 (orrery/coalton/core:cl-count-by-severity
             (orrery/coalton/core:cl-audit-critical) t3))))

;;; --- Deterministic hashing ---

(define-test (audit-trail-tests deterministic-hashing)
  "Same inputs produce same hashes (determinism)."
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (t1a (orrery/coalton/core:cl-append-entry
               #'%test-hash-fn trail
               100 (orrery/coalton/core:cl-audit-session-lifecycle)
               (orrery/coalton/core:cl-audit-info)
               "agent" "msg" "data"))
         (t1b (orrery/coalton/core:cl-append-entry
               #'%test-hash-fn trail
               100 (orrery/coalton/core:cl-audit-session-lifecycle)
               (orrery/coalton/core:cl-audit-info)
               "agent" "msg" "data")))
    (is string= (orrery/coalton/core:cl-trail-tip-hash t1a)
        (orrery/coalton/core:cl-trail-tip-hash t1b))))

;;; --- Immutability (original trail unchanged) ---

(define-test (audit-trail-tests immutability)
  "Appending returns new trail; original is unchanged."
  (let* ((trail (orrery/coalton/core:cl-empty-trail))
         (t1 (orrery/coalton/core:cl-append-entry
              #'%test-hash-fn trail
              100 (orrery/coalton/core:cl-audit-session-lifecycle)
              (orrery/coalton/core:cl-audit-info)
              "a" "s1" "{}")))
    ;; Original should still be empty
    (is = 0 (orrery/coalton/core:cl-trail-count trail))
    (is = 1 (orrery/coalton/core:cl-trail-count t1))))

;;; --- Hash input determinism ---

(define-test (audit-trail-tests hash-input-format)
  "Hash input string has pipe-delimited fields."
  (let ((input (coalton:coalton
                (orrery/coalton/core:hash-input
                 0 1000
                 orrery/coalton/core:AuditSessionLifecycle
                 orrery/coalton/core:AuditInfo
                 "actor" "summary" "detail"
                 (orrery/coalton/core:genesis-hash coalton:Unit)))))
    (true (search "|" input))
    (true (search "session-lifecycle" input))
    (true (search "info" input))
    (true (search "actor" input))
    (true (search "summary" input))
    (true (search "detail" input))))
