;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-fixture-checksum-registry-tests.lisp
;;;   Tests for Epic 3 T1-T6 fixture checksum registry + rerun consistency gate.
;;;
;;; Bead: agent-orrery-d2it

(in-package #:orrery/harness-tests)

(define-test t1-t6-fixture-checksum-registry-suite)

;;; ── helpers ──────────────────────────────────────────────────────────────────

(defun %make-full-checksum-map ()
  "Return a complete artifact checksum map with all required kinds."
  (list (cons "transcript" "abc123")
        (cons "screenshot"  "def456")
        (cons "asciicast"   "ghi789")
        (cons "report"      "jkl012")))

(defun %make-partial-checksum-map ()
  "Return a partial artifact checksum map missing 'asciicast' and 'report'."
  (list (cons "transcript" "abc123")
        (cons "screenshot"  "def456")))

(defun %make-six-entries ()
  "Build six passing fixture-checksum-entries for T1-T6."
  (mapcar (lambda (sid)
            (orrery/adapter:make-checksum-entry
             sid (%make-full-checksum-map) "digest-abc"))
          '(:T1 :T2 :T3 :T4 :T5 :T6)))

;;; ── basic construction ───────────────────────────────────────────────────────

(define-test (t1-t6-fixture-checksum-registry-suite make-entry-pass)
  (let ((e (orrery/adapter:make-checksum-entry :T1 (%make-full-checksum-map) "td1")))
    (is eq :T1 (orrery/adapter:fce-scenario-id e)
        "scenario-id is :T1")
    (is eq :pass (orrery/adapter:fce-verdict e)
        "verdict is :pass with full artifact map")
    (is equal '() (orrery/adapter:fce-missing-keys e)
        "no missing keys")
    (false (string= "" (orrery/adapter:fce-command-fingerprint e))
           "command fingerprint is non-empty")))

(define-test (t1-t6-fixture-checksum-registry-suite make-entry-missing-artifacts)
  (let ((e (orrery/adapter:make-checksum-entry :T2 (%make-partial-checksum-map) "td2")))
    (is eq :missing (orrery/adapter:fce-verdict e)
        "verdict is :missing with partial artifact map")
    (true (member "asciicast" (orrery/adapter:fce-missing-keys e) :test #'equal)
          "asciicast listed as missing")
    (true (member "report" (orrery/adapter:fce-missing-keys e) :test #'equal)
          "report listed as missing")))

;;; ── registry construction ────────────────────────────────────────────────────

(define-test (t1-t6-fixture-checksum-registry-suite build-registry-closed)
  (let* ((entries (%make-six-entries))
         (reg (orrery/adapter:build-registry-from-entries entries)))
    (is eq :closed (orrery/adapter:evaluate-registry-closure reg)
        "full passing registry yields :closed verdict")
    (is = 0 (orrery/adapter:fcr-drift-count reg)
        "no drift")
    (is = 0 (orrery/adapter:fcr-missing-count reg)
        "no missing")))

(define-test (t1-t6-fixture-checksum-registry-suite build-registry-open-when-incomplete)
  (let* ((entries (list (orrery/adapter:make-checksum-entry :T1 (%make-full-checksum-map) "d1")
                        (orrery/adapter:make-checksum-entry :T2 (%make-full-checksum-map) "d2")))
         (reg (orrery/adapter:build-registry-from-entries entries)))
    (is eq :open (orrery/adapter:evaluate-registry-closure reg)
        "registry with fewer than 6 scenarios is :open")))

(define-test (t1-t6-fixture-checksum-registry-suite build-registry-rejected-on-missing-artifacts)
  (let* ((bad-entry (orrery/adapter:make-checksum-entry :T1 (%make-partial-checksum-map) "d1"))
         (rest (mapcar (lambda (sid)
                         (orrery/adapter:make-checksum-entry sid (%make-full-checksum-map) "d"))
                       '(:T2 :T3 :T4 :T5 :T6)))
         (entries (cons bad-entry rest))
         (reg (orrery/adapter:build-registry-from-entries entries)))
    (is eq :rejected (orrery/adapter:evaluate-registry-closure reg)
        "registry with missing artifacts yields :rejected verdict")
    (is = 1 (orrery/adapter:fcr-missing-count reg)
        "missing-count is 1")))

;;; ── JSON serialization ───────────────────────────────────────────────────────

(define-test (t1-t6-fixture-checksum-registry-suite registry-json-contains-verdict)
  (let* ((entries (%make-six-entries))
         (reg (orrery/adapter:build-registry-from-entries entries))
         (json (orrery/adapter:registry->json reg)))
    (true (search "\"closure_verdict\":\"CLOSED\"" json)
          "JSON contains closure_verdict=CLOSED")
    (true (search "\"T1\"" json) "JSON contains T1")
    (true (search "\"T6\"" json) "JSON contains T6")
    (true (search "\"canonical_command\"" json) "JSON has canonical_command field")))

;;; ── rerun consistency ────────────────────────────────────────────────────────

(define-test (t1-t6-fixture-checksum-registry-suite rerun-stable-when-digests-match)
  (let* ((old-entries (%make-six-entries))
         (new-entries (%make-six-entries))
         (old-reg (orrery/adapter:build-registry-from-entries old-entries))
         (new-reg (orrery/adapter:build-registry-from-entries new-entries))
         (verdicts (orrery/adapter:compute-rerun-consistency-verdicts old-reg new-reg)))
    (is = 6 (length verdicts)
        "six consistency verdicts returned")
    (true (every (lambda (v) (eq (orrery/adapter:rcv-status v) :stable)) verdicts)
          "all verdicts :stable when digests match")))

(define-test (t1-t6-fixture-checksum-registry-suite rerun-drifted-when-digest-changes)
  (let* ((old-entries (list (orrery/adapter:make-checksum-entry :T1 (%make-full-checksum-map) "old-digest")))
         (new-entries (list (orrery/adapter:make-checksum-entry :T1 (%make-full-checksum-map) "new-digest-different")))
         (old-reg (orrery/adapter:build-registry-from-entries old-entries))
         (new-reg (orrery/adapter:build-registry-from-entries new-entries))
         (verdicts (orrery/adapter:compute-rerun-consistency-verdicts old-reg new-reg)))
    (let ((t1v (find :T1 verdicts :key #'orrery/adapter:rcv-scenario-id)))
      (is eq :drifted (orrery/adapter:rcv-status t1v)
          "T1 verdict is :drifted when digest changes"))))

(define-test (t1-t6-fixture-checksum-registry-suite rerun-missing-fails-closed)
  (let* ((old-entries (%make-six-entries))
         (new-entries (list (orrery/adapter:make-checksum-entry :T1 (%make-full-checksum-map) "d1")))
         (old-reg (orrery/adapter:build-registry-from-entries old-entries))
         (new-reg (orrery/adapter:build-registry-from-entries new-entries))
         (verdicts (orrery/adapter:compute-rerun-consistency-verdicts old-reg new-reg)))
    (let ((missing-count (count :missing verdicts :key #'orrery/adapter:rcv-status)))
      (is = 5 missing-count
          "5 scenarios missing in new run → 5 :missing verdicts (fail closed)"))))

;;; ── rerun JSON ───────────────────────────────────────────────────────────────

(define-test (t1-t6-fixture-checksum-registry-suite rerun-verdicts-json-stable)
  (let* ((old-reg (orrery/adapter:build-registry-from-entries (%make-six-entries)))
         (new-reg (orrery/adapter:build-registry-from-entries (%make-six-entries)))
         (verdicts (orrery/adapter:compute-rerun-consistency-verdicts old-reg new-reg))
         (json (orrery/adapter:rerun-verdicts->json verdicts)))
    (true (search "\"gate_verdict\":\"STABLE\"" json)
          "gate verdict is STABLE for matching registries")))
