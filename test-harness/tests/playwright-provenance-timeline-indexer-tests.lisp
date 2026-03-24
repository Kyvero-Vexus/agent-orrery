;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-provenance-timeline-indexer-tests.lisp
;;;   Tests for the S1-S6 provenance timeline indexer.
;;;   Bead: agent-orrery-jyhv

(in-package #:orrery/harness-tests)

(define-test playwright-provenance-timeline-indexer-suite)

;;; ─── Helpers ─────────────────────────────────────────────────────────────────

(defun %make-pte (scenario-id idx &key (ss "abc") (tr "def") (drift nil))
  (orrery/adapter:build-provenance-timeline-entry
   scenario-id idx ss tr :timestamp 1000 :drift-rationale drift))

;;; ─── build-provenance-timeline-entry ─────────────────────────────────────────

(define-test (playwright-provenance-timeline-indexer-suite entry-stable-when-digests-present)
  (let ((e (%make-pte "S1" 0 :ss "s1hash" :tr "t1hash")))
    (true  (orrery/adapter:pte-stable-p e))
    (is string= "S1" (orrery/adapter:pte-scenario-id e))
    (is = 0 (orrery/adapter:pte-rerun-index e))
    (is string= "s1hash" (orrery/adapter:pte-screenshot-digest e))
    (is string= "t1hash" (orrery/adapter:pte-trace-digest e))
    (is string= "" (orrery/adapter:pte-drift-rationale e))))

(define-test (playwright-provenance-timeline-indexer-suite entry-unstable-when-screenshot-empty)
  (let ((e (%make-pte "S2" 1 :ss "" :tr "t1")))
    (false (orrery/adapter:pte-stable-p e))))

(define-test (playwright-provenance-timeline-indexer-suite entry-unstable-when-trace-empty)
  (let ((e (%make-pte "S3" 2 :ss "s1" :tr "")))
    (false (orrery/adapter:pte-stable-p e))))

(define-test (playwright-provenance-timeline-indexer-suite entry-drift-rationale-preserved)
  (let ((e (%make-pte "S4" 0 :ss "x" :tr "y" :drift "screenshot-digest changed")))
    (is string= "screenshot-digest changed" (orrery/adapter:pte-drift-rationale e))))

(define-test (playwright-provenance-timeline-indexer-suite entry-fingerprint-deterministic)
  ;; Same inputs → same fingerprint
  (let ((fp1 (orrery/adapter:pte-command-fingerprint (%make-pte "S1" 0)))
        (fp2 (orrery/adapter:pte-command-fingerprint (%make-pte "S1" 0))))
    (is = fp1 fp2)))

;;; ─── build-scenario-provenance-timeline ──────────────────────────────────────

(define-test (playwright-provenance-timeline-indexer-suite timeline-stable-same-digests)
  (let* ((entries (list (%make-pte "S1" 0 :ss "h1" :tr "t1")
                        (%make-pte "S1" 1 :ss "h1" :tr "t1")
                        (%make-pte "S1" 2 :ss "h1" :tr "t1")))
         (tl (orrery/adapter:build-scenario-provenance-timeline "S1" entries)))
    (true  (orrery/adapter:spt-lineage-stable-p tl))
    (is = 3 (orrery/adapter:spt-entry-count tl))
    (is = 0 (length (orrery/adapter:spt-drift-events tl)))))

(define-test (playwright-provenance-timeline-indexer-suite timeline-drift-detected)
  (let* ((entries (list (%make-pte "S2" 0 :ss "h1" :tr "t1")
                        (%make-pte "S2" 1 :ss "h2" :tr "t1")))  ; digest changed
         (tl (orrery/adapter:build-scenario-provenance-timeline "S2" entries)))
    ;; fingerprint changes between rerun-0 and rerun-1 (different rerun-index)
    ;; so lineage-stable-p might be nil; drift-events captures screenshot change
    (is = 2 (orrery/adapter:spt-entry-count tl))
    (true (plusp (length (orrery/adapter:spt-drift-events tl))))))

(define-test (playwright-provenance-timeline-indexer-suite timeline-digest-history-length)
  (let* ((entries (list (%make-pte "S3" 0 :ss "a" :tr "x")
                        (%make-pte "S3" 1 :ss "b" :tr "x")))
         (tl (orrery/adapter:build-scenario-provenance-timeline "S3" entries)))
    (is = 2 (length (orrery/adapter:spt-digest-history     tl)))
    (is = 2 (length (orrery/adapter:spt-fingerprint-lineage tl)))))

;;; ─── build-playwright-provenance-index ───────────────────────────────────────

(defun %stable-timeline (id)
  ;; All entries identical → no drift
  (orrery/adapter:build-scenario-provenance-timeline
   id
   (list (%make-pte id 0 :ss "stable-hash" :tr "stable-trace")
         (%make-pte id 0 :ss "stable-hash" :tr "stable-trace"))))

(define-test (playwright-provenance-timeline-indexer-suite index-closure-ready-all-stable)
  ;; We need same rerun-index to get same command-fingerprint → no drift
  (let* ((tls (list (%stable-timeline "S1")
                    (%stable-timeline "S2")
                    (%stable-timeline "S3")
                    (%stable-timeline "S4")
                    (%stable-timeline "S5")
                    (%stable-timeline "S6")))
         (idx (orrery/adapter:build-playwright-provenance-index "run-001" tls)))
    (true  (orrery/adapter:ppi-all-stable-p    idx))
    (is = 0 (orrery/adapter:ppi-total-drift-events idx))
    (true  (orrery/adapter:ppi-closure-ready-p idx))
    (false (member :closure-not-ready (orrery/adapter:ppi-alarm-codes idx)))))

(define-test (playwright-provenance-timeline-indexer-suite index-not-ready-on-drift)
  (let* ((drifty
          (orrery/adapter:build-scenario-provenance-timeline
           "S1"
           (list (%make-pte "S1" 0 :ss "x" :tr "t")
                 (%make-pte "S1" 1 :ss "y" :tr "t"))))
         (idx (orrery/adapter:build-playwright-provenance-index
               "run-002" (list drifty))))
    (false (orrery/adapter:ppi-closure-ready-p idx))
    (true  (member :closure-not-ready (orrery/adapter:ppi-alarm-codes idx)))))

(define-test (playwright-provenance-timeline-indexer-suite index-alarm-codes-accumulated)
  (let* ((e1 (%make-pte "S1" 0 :ss "" :tr ""))   ; unstable
         (tl (orrery/adapter:build-scenario-provenance-timeline "S1" (list e1)))
         (idx (orrery/adapter:build-playwright-provenance-index "run-003" (list tl))))
    (false (orrery/adapter:ppi-closure-ready-p idx))
    (is string= "run-003" (orrery/adapter:ppi-run-id idx))))
