;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; audit-trail.lisp — Coalton pure audit trail with cryptographic hash chain
;;;
;;; Append-only typed event log. Every entry carries a SHA-256 hash of
;;; (prev-hash ++ payload), forming a tamper-evident chain.
;;; All functions pure and total. No IO.
;;;
;;; Bead: agent-orrery-8cn

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Event Categories ───

  (define-type AuditCategory
    "Category of auditable event."
    AuditSessionLifecycle     ; session create/close/error
    AuditCronExecution        ; cron job triggered/completed/failed
    AuditPolicyChange         ; budget/routing policy modified
    AuditConfigChange         ; runtime configuration changed
    AuditAlertFired           ; alert/notification dispatched
    AuditGateDecision         ; gate pass/fail decision
    AuditModelRouting         ; model selection/fallback
    AuditAdapterEvent         ; adapter connect/disconnect/error
    AuditManualAction)        ; human-initiated override

  (declare audit-category-label (AuditCategory -> String))
  (define (audit-category-label cat)
    (match cat
      ((AuditSessionLifecycle) "session-lifecycle")
      ((AuditCronExecution)    "cron-execution")
      ((AuditPolicyChange)     "policy-change")
      ((AuditConfigChange)     "config-change")
      ((AuditAlertFired)       "alert-fired")
      ((AuditGateDecision)     "gate-decision")
      ((AuditModelRouting)     "model-routing")
      ((AuditAdapterEvent)     "adapter-event")
      ((AuditManualAction)     "manual-action")))

  ;; ─── Severity ───

  (define-type AuditSeverity
    "Severity level for audit entry."
    AuditTrace     ; routine, low-signal
    AuditInfo      ; normal operation
    AuditWarning   ; notable, may require attention
    AuditCritical) ; requires immediate attention

  (declare audit-severity-label (AuditSeverity -> String))
  (define (audit-severity-label sev)
    (match sev
      ((AuditTrace)    "trace")
      ((AuditInfo)     "info")
      ((AuditWarning)  "warning")
      ((AuditCritical) "critical")))

  (declare audit-severity-score (AuditSeverity -> Integer))
  (define (audit-severity-score sev)
    (match sev
      ((AuditTrace)    0)
      ((AuditInfo)     1)
      ((AuditWarning)  2)
      ((AuditCritical) 3)))

  ;; ─── Hash Representation ───
  ;; We represent SHA-256 hashes as hex-encoded strings (64 chars).
  ;; The actual hashing is done by the CL bridge; the Coalton layer
  ;; treats hashes as opaque strings and chains them structurally.

  (define-type AuditHash
    "Opaque SHA-256 hash (hex string)."
    (AuditHash String))

  (declare audit-hash-value (AuditHash -> String))
  (define (audit-hash-value h)
    (match h ((AuditHash s) s)))

  (declare genesis-hash (Unit -> AuditHash))
  (define (genesis-hash _u)
    "The sentinel hash for the first entry in a chain."
    (AuditHash "0000000000000000000000000000000000000000000000000000000000000000"))

  ;; ─── Audit Entry ───

  (define-type AuditEntry
    "One immutable audit trail entry."
    (AuditEntry Integer          ; sequence number (0-based)
                Integer          ; timestamp (unix epoch seconds)
                AuditCategory    ; event category
                AuditSeverity    ; severity level
                String           ; actor (who/what caused it)
                String           ; summary (human-readable)
                String           ; detail (structured payload, e.g. JSON)
                AuditHash        ; this entry's hash
                AuditHash))      ; previous entry's hash

  (declare ae-seq (AuditEntry -> Integer))
  (define (ae-seq e)
    (match e ((AuditEntry s _ _ _ _ _ _ _ _) s)))

  (declare ae-timestamp (AuditEntry -> Integer))
  (define (ae-timestamp e)
    (match e ((AuditEntry _ ts _ _ _ _ _ _ _) ts)))

  (declare ae-category (AuditEntry -> AuditCategory))
  (define (ae-category e)
    (match e ((AuditEntry _ _ cat _ _ _ _ _ _) cat)))

  (declare ae-severity (AuditEntry -> AuditSeverity))
  (define (ae-severity e)
    (match e ((AuditEntry _ _ _ sev _ _ _ _ _) sev)))

  (declare ae-actor (AuditEntry -> String))
  (define (ae-actor e)
    (match e ((AuditEntry _ _ _ _ a _ _ _ _) a)))

  (declare ae-summary (AuditEntry -> String))
  (define (ae-summary e)
    (match e ((AuditEntry _ _ _ _ _ s _ _ _) s)))

  (declare ae-detail (AuditEntry -> String))
  (define (ae-detail e)
    (match e ((AuditEntry _ _ _ _ _ _ d _ _) d)))

  (declare ae-hash (AuditEntry -> AuditHash))
  (define (ae-hash e)
    (match e ((AuditEntry _ _ _ _ _ _ _ h _) h)))

  (declare ae-prev-hash (AuditEntry -> AuditHash))
  (define (ae-prev-hash e)
    (match e ((AuditEntry _ _ _ _ _ _ _ _ ph) ph)))

  ;; ─── Audit Trail (the chain) ───

  (define-type AuditTrail
    "Append-only audit trail. Entries stored newest-first for O(1) append."
    (AuditTrail Integer           ; entry count
                (List AuditEntry)  ; entries (newest first)
                AuditHash))        ; latest hash (tip of chain)

  (declare trail-count (AuditTrail -> Integer))
  (define (trail-count t)
    (match t ((AuditTrail c _ _) c)))

  (declare trail-entries (AuditTrail -> (List AuditEntry)))
  (define (trail-entries t)
    (match t ((AuditTrail _ es _) es)))

  (declare trail-tip-hash (AuditTrail -> AuditHash))
  (define (trail-tip-hash t)
    (match t ((AuditTrail _ _ h) h)))

  (declare empty-trail (Unit -> AuditTrail))
  (define (empty-trail _u)
    "Create an empty audit trail."
    (AuditTrail 0 Nil (genesis-hash Unit)))

  ;; ─── Hash Input Construction ───
  ;; We build a deterministic string from the entry fields + prev-hash.
  ;; The CL bridge hashes this string with SHA-256.

  (declare %int-to-str (Integer -> String))
  (define (%int-to-str n)
    (lisp String (n) (cl:princ-to-string n)))

  (declare hash-input (Integer -> Integer -> AuditCategory -> AuditSeverity
                       -> String -> String -> String -> AuditHash -> String))
  (define (hash-input seq ts cat sev actor summary detail prev-hash)
    "Build deterministic pre-image string for hashing."
    (mconcat
     (make-list
      (%int-to-str seq) "|"
      (%int-to-str ts) "|"
      (audit-category-label cat) "|"
      (audit-severity-label sev) "|"
      actor "|"
      summary "|"
      detail "|"
      (audit-hash-value prev-hash))))

  ;; ─── Entry Construction ───
  ;; The hash-fn is passed in so the Coalton layer stays pure.
  ;; In production the CL bridge supplies SHA-256; in tests a stub.

  (declare make-audit-entry ((String -> AuditHash) -> AuditTrail
                             -> Integer -> AuditCategory -> AuditSeverity
                             -> String -> String -> String -> AuditEntry))
  (define (make-audit-entry hash-fn trail ts cat sev actor summary detail)
    "Create a new audit entry chained to the trail's tip."
    (let ((seq (trail-count trail))
          (prev (trail-tip-hash trail)))
      (let ((input (hash-input seq ts cat sev actor summary detail prev)))
        (let ((h (hash-fn input)))
          (AuditEntry seq ts cat sev actor summary detail h prev)))))

  ;; ─── Append ───

  (declare append-entry ((String -> AuditHash) -> AuditTrail
                         -> Integer -> AuditCategory -> AuditSeverity
                         -> String -> String -> String -> AuditTrail))
  (define (append-entry hash-fn trail ts cat sev actor summary detail)
    "Append a new entry to the trail. Returns new trail."
    (let ((entry (make-audit-entry hash-fn trail ts cat sev actor summary detail)))
      (AuditTrail (+ 1 (trail-count trail))
                  (Cons entry (trail-entries trail))
                  (ae-hash entry))))

  ;; ─── Chain Verification ───

  (declare %recompute-hash ((String -> AuditHash) -> AuditEntry -> AuditHash))
  (define (%recompute-hash hash-fn entry)
    "Recompute the hash for an entry from its fields."
    (hash-fn (hash-input (ae-seq entry) (ae-timestamp entry)
                         (ae-category entry) (ae-severity entry)
                         (ae-actor entry) (ae-summary entry)
                         (ae-detail entry) (ae-prev-hash entry))))

  (declare verify-chain-link ((String -> AuditHash) -> AuditEntry -> Boolean))
  (define (verify-chain-link hash-fn entry)
    "Verify a single entry's hash is correctly computed."
    (== (audit-hash-value (%recompute-hash hash-fn entry))
        (audit-hash-value (ae-hash entry))))

  (declare %verify-entries ((String -> AuditHash) -> (List AuditEntry) -> Boolean))
  (define (%verify-entries hash-fn entries)
    "Walk entries newest-first. Verify each hash recomputes and prev-hash links."
    (match entries
      ((Nil) True)
      ((Cons e rest)
       (if (verify-chain-link hash-fn e)
           (match rest
             ((Nil)
              ;; Oldest entry: prev-hash must be genesis
              (== (audit-hash-value (ae-prev-hash e))
                  (audit-hash-value (genesis-hash Unit))))
             ((Cons older _)
              ;; This entry's prev-hash must equal the older entry's hash
              (if (== (audit-hash-value (ae-prev-hash e))
                      (audit-hash-value (ae-hash older)))
                  (%verify-entries hash-fn rest)
                  False)))
           False))))

  (declare verify-trail ((String -> AuditHash) -> AuditTrail -> Boolean))
  (define (verify-trail hash-fn trail)
    "Verify the entire audit trail hash chain. O(n)."
    (match (trail-entries trail)
      ((Nil) True)
      ((Cons newest _)
       ;; Tip hash must match newest entry's hash
       (if (== (audit-hash-value (ae-hash newest))
               (audit-hash-value (trail-tip-hash trail)))
           (%verify-entries hash-fn (trail-entries trail))
           False))))

  ;; ─── Query Helpers ───

  (declare filter-by-category (AuditCategory -> AuditTrail -> (List AuditEntry)))
  (define (filter-by-category cat trail)
    "Return entries matching category (newest first)."
    (filter (fn (e) (== (audit-category-label (ae-category e))
                        (audit-category-label cat)))
            (trail-entries trail)))

  (declare filter-by-severity-min (AuditSeverity -> AuditTrail -> (List AuditEntry)))
  (define (filter-by-severity-min min-sev trail)
    "Return entries at or above severity threshold (newest first)."
    (filter (fn (e) (>= (audit-severity-score (ae-severity e))
                        (audit-severity-score min-sev)))
            (trail-entries trail)))

  (declare filter-by-time-range (Integer -> Integer -> AuditTrail -> (List AuditEntry)))
  (define (filter-by-time-range start-ts end-ts trail)
    "Return entries within [start-ts, end-ts] (newest first)."
    (filter (fn (e) (if (>= (ae-timestamp e) start-ts)
                        (<= (ae-timestamp e) end-ts)
                        False))
            (trail-entries trail)))

  (declare trail-latest (AuditTrail -> (Optional AuditEntry)))
  (define (trail-latest trail)
    "Return the most recent entry, or None."
    (match (trail-entries trail)
      ((Nil) None)
      ((Cons e _) (Some e))))

  (declare count-by-severity (AuditSeverity -> AuditTrail -> UFix))
  (define (count-by-severity sev trail)
    "Count entries of exact severity."
    (length (filter (fn (e) (== (audit-severity-score (ae-severity e))
                                (audit-severity-score sev)))
                    (trail-entries trail)))))

;;; ─── CL Bridge ───

(cl:defun cl-empty-trail ()
  "CL-callable: create an empty audit trail."
  (coalton:coalton (empty-trail Unit)))

(cl:defvar *%audit-hash-fn* cl:nil
  "Dynamic binding for the CL hash function used by audit trail bridge.")

(coalton-toplevel
  (declare %dynamic-hash-fn (String -> AuditHash))
  (define (%dynamic-hash-fn input)
    "Call the dynamically-bound CL hash function."
    (AuditHash (lisp String (input)
                 (cl:funcall *%audit-hash-fn* input)))))

(cl:defun cl-append-entry (hash-fn trail ts category severity actor summary detail)
  "CL-callable: append an entry. HASH-FN is a CL function (string -> string)."
  (cl:let ((*%audit-hash-fn* hash-fn))
    (coalton:coalton
     (append-entry
      %dynamic-hash-fn
      (lisp AuditTrail () trail)
      (lisp Integer () ts)
      (lisp AuditCategory () category)
      (lisp AuditSeverity () severity)
      (lisp String () actor)
      (lisp String () summary)
      (lisp String () detail)))))

(cl:defun cl-verify-trail (hash-fn trail)
  "CL-callable: verify hash chain integrity."
  (cl:let ((*%audit-hash-fn* hash-fn))
    (coalton:coalton
     (verify-trail
      %dynamic-hash-fn
      (lisp AuditTrail () trail)))))

(cl:defun cl-trail-count (trail)
  "CL-callable: return entry count."
  (coalton:coalton (trail-count (lisp AuditTrail () trail))))

(cl:defun cl-trail-tip-hash (trail)
  "CL-callable: return tip hash as string."
  (coalton:coalton (audit-hash-value (trail-tip-hash (lisp AuditTrail () trail)))))

(cl:defun cl-audit-session-lifecycle ()
  (coalton:coalton AuditSessionLifecycle))

(cl:defun cl-audit-cron-execution ()
  (coalton:coalton AuditCronExecution))

(cl:defun cl-audit-policy-change ()
  (coalton:coalton AuditPolicyChange))

(cl:defun cl-audit-config-change ()
  (coalton:coalton AuditConfigChange))

(cl:defun cl-audit-alert-fired ()
  (coalton:coalton AuditAlertFired))

(cl:defun cl-audit-gate-decision ()
  (coalton:coalton AuditGateDecision))

(cl:defun cl-audit-model-routing ()
  (coalton:coalton AuditModelRouting))

(cl:defun cl-audit-adapter-event ()
  (coalton:coalton AuditAdapterEvent))

(cl:defun cl-audit-manual-action ()
  (coalton:coalton AuditManualAction))

(cl:defun cl-audit-trace ()
  (coalton:coalton AuditTrace))

(cl:defun cl-audit-info ()
  (coalton:coalton AuditInfo))

(cl:defun cl-audit-warning ()
  (coalton:coalton AuditWarning))

(cl:defun cl-audit-critical ()
  (coalton:coalton AuditCritical))

(cl:defun cl-entry-seq (e)
  (coalton:coalton (ae-seq (lisp AuditEntry () e))))

(cl:defun cl-entry-timestamp (e)
  (coalton:coalton (ae-timestamp (lisp AuditEntry () e))))

(cl:defun cl-entry-category-label (e)
  (coalton:coalton (audit-category-label (ae-category (lisp AuditEntry () e)))))

(cl:defun cl-entry-severity-label (e)
  (coalton:coalton (audit-severity-label (ae-severity (lisp AuditEntry () e)))))

(cl:defun cl-entry-actor (e)
  (coalton:coalton (ae-actor (lisp AuditEntry () e))))

(cl:defun cl-entry-summary (e)
  (coalton:coalton (ae-summary (lisp AuditEntry () e))))

(cl:defun cl-entry-detail (e)
  (coalton:coalton (ae-detail (lisp AuditEntry () e))))

(cl:defun cl-entry-hash (e)
  (coalton:coalton (audit-hash-value (ae-hash (lisp AuditEntry () e)))))

(cl:defun cl-entry-prev-hash (e)
  (coalton:coalton (audit-hash-value (ae-prev-hash (lisp AuditEntry () e)))))

;;; For getting individual entries from the CL side, we use the
;;; make-audit-entry function directly and return it.
;;; The cl-entry-* accessors work on AuditEntry values.

(cl:defun cl-make-single-entry (hash-fn trail ts category severity actor summary detail)
  "CL-callable: create entry without appending to trail. Returns entry."
  (cl:let ((*%audit-hash-fn* hash-fn))
    (coalton:coalton
     (make-audit-entry
      %dynamic-hash-fn
      (lisp AuditTrail () trail)
      (lisp Integer () ts)
      (lisp AuditCategory () category)
      (lisp AuditSeverity () severity)
      (lisp String () actor)
      (lisp String () summary)
      (lisp String () detail)))))

(cl:defun cl-filter-by-category (cat trail)
  "CL-callable: filter trail by category."
  (coalton:coalton
   (filter-by-category
    (lisp AuditCategory () cat)
    (lisp AuditTrail () trail))))

(cl:defun cl-filter-by-severity-min (sev trail)
  "CL-callable: filter trail by minimum severity."
  (coalton:coalton
   (filter-by-severity-min
    (lisp AuditSeverity () sev)
    (lisp AuditTrail () trail))))

(cl:defun cl-count-by-severity (sev trail)
  "CL-callable: count entries of exact severity."
  (coalton:coalton
   (count-by-severity
    (lisp AuditSeverity () sev)
    (lisp AuditTrail () trail))))
