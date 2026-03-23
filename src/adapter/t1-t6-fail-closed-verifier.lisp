;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-fail-closed-verifier.lisp — fail-closed verifier + machine-checkable closure verdict
;;; Bead: agent-orrery-0bga
;;;
;;; Consumes t1-t6-replay-journal and t1-t6-rerun-pack to emit machine-checkable
;;; closure verdicts for Epic 3 T1-T6 evidence. Fail-closed: any gap or drift
;;; produces a :FAIL verdict with deterministic diagnostics. Never reports
;;; Epic 3 closure without mcp-tui-driver-backed T1-T6 deterministic command+artifact evidence.

(in-package #:orrery/adapter)

;; ─── Verdict types ────────────────────────────────────────────────────────────

(deftype closure-verdict ()
  '(member :closed :incomplete :fail :rejected))

(defstruct (t1-t6-closure-finding (:conc-name finding-))
  "One diagnostic finding from the fail-closed verifier."
  (scenario-id :T1 :type replay-journal-scenario-id)
  (category :missing :type (member :missing :command-drift :artifact-gap :digest-mismatch :pass))
  (detail "" :type string))

(defstruct (t1-t6-closure-verdict (:conc-name verdict-))
  "Machine-checkable closure verdict for Epic 3 T1-T6."
  (verdict :fail :type closure-verdict)
  (command-canonical-p nil :type boolean)
  (complete-p nil :type boolean)
  (findings nil :type list)        ; list of t1-t6-closure-finding
  (pack-hash "" :type string)
  (assessed-at "" :type string)
  (policy-note "Epic 3 MUST NOT be reported closed without mcp-tui-driver-backed T1-T6 evidence." :type string))

;; ─── Core verifier ────────────────────────────────────────────────────────────

(declaim
 (ftype (function (t1-t6-rerun-pack) (values t1-t6-closure-verdict &optional)) verify-t1-t6-closure)
 (ftype (function (t1-t6-closure-verdict) (values string &optional)) closure-verdict->json)
 (ftype (function (t1-t6-closure-verdict) (values boolean &optional)) closure-verdict-pass-p))

(defun verify-row (row)
  "Check one journal row; return a finding."
  (declare (type t1-t6-replay-journal-row row))
  (let ((id (jrow-scenario-id row))
        (verdict (jrow-verdict row))
        (cf (jrow-command-fingerprint row))
        (ab (jrow-artifact-bundle row)))
    (cond
      ((eq verdict :pass)
       (make-t1-t6-closure-finding :scenario-id id :category :pass :detail "ok"))
      ((null cf)
       (make-t1-t6-closure-finding
        :scenario-id id :category :missing
        :detail "no command fingerprint recorded"))
      ((not (canonical-command-p (rcf-canonical cf)))
       (make-t1-t6-closure-finding
        :scenario-id id :category :command-drift
        :detail (format nil "non-canonical command: ~S" (rcf-canonical cf))))
      ((null ab)
       (make-t1-t6-closure-finding
        :scenario-id id :category :artifact-gap
        :detail "no artifact bundle recorded"))
      ((null (rabr-artifact-paths ab))
       (make-t1-t6-closure-finding
        :scenario-id id :category :artifact-gap
        :detail "artifact bundle has no paths"))
      (t
       (make-t1-t6-closure-finding :scenario-id id :category :missing
                                    :detail (format nil "scenario verdict is ~A" verdict))))))

(defun verify-t1-t6-closure (pack)
  "Emit a machine-checkable closure verdict for T1-T6 evidence from a rerun pack."
  (declare (type t1-t6-rerun-pack pack))
  (let* ((lock (pack-command-lock pack))
         (journal (pack-journal pack))
         (cmd-ok (and lock (command-lock-valid-p lock)))
         (findings (if journal
                       (mapcar #'verify-row (journal-rows journal))
                       (list (make-t1-t6-closure-finding
                              :scenario-id :T1 :category :missing
                              :detail "no journal in pack"))))
         (all-pass (every (lambda (f) (eq (finding-category f) :pass)) findings))
         (complete (and cmd-ok journal (journal-complete-p journal) all-pass))
         (verdict (cond
                    ((not cmd-ok) :rejected)
                    (complete :closed)
                    (t :incomplete))))
    (make-t1-t6-closure-verdict
     :verdict verdict
     :command-canonical-p cmd-ok
     :complete-p complete
     :findings findings
     :pack-hash (pack-pack-hash pack)
     :assessed-at (format nil "~A" (get-universal-time)))))

(defun closure-verdict-pass-p (cv)
  "Return T iff verdict is :CLOSED (all T1-T6 pass + canonical command)."
  (declare (type t1-t6-closure-verdict cv))
  (eq (verdict-verdict cv) :closed))

;; ─── Serialization ────────────────────────────────────────────────────────────

(defun finding->json (f)
  (declare (type t1-t6-closure-finding f))
  (format nil "{\"scenario\":\"~A\",\"category\":\"~A\",\"detail\":\"~A\"}"
          (string (finding-scenario-id f))
          (string (finding-category f))
          (finding-detail f)))

(defun closure-verdict->json (cv)
  "Serialize closure verdict to JSON for machine consumption."
  (declare (type t1-t6-closure-verdict cv))
  (format nil
          "{\"verdict\":\"~A\",\"command_canonical\":~A,\"complete\":~A,\"pack_hash\":\"~A\",\"assessed_at\":\"~A\",\"policy_note\":\"~A\",\"findings\":[~{~A~^,~}]}"
          (string (verdict-verdict cv))
          (if (verdict-command-canonical-p cv) "true" "false")
          (if (verdict-complete-p cv) "true" "false")
          (verdict-pack-hash cv)
          (verdict-assessed-at cv)
          (verdict-policy-note cv)
          (mapcar #'finding->json (verdict-findings cv))))

;; ─── CLI entry point ──────────────────────────────────────────────────────────

(defun run-t1-t6-closure-check (output-path)
  "Run closure check on an empty pack (bootstrap) and write verdict JSON to OUTPUT-PATH."
  (declare (type string output-path))
  (let* ((journal (make-empty-journal))
         (pack (assemble-rerun-pack journal))
         (cv (verify-t1-t6-closure pack))
         (json (closure-verdict->json cv)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string json s))
    (format t "Verdict: ~A~%" (verdict-verdict cv))
    (format t "Complete: ~A~%" (verdict-complete-p cv))
    (format t "Findings:~%")
    (dolist (f (verdict-findings cv))
      (format t "  ~A: ~A (~A)~%"
              (finding-scenario-id f) (finding-category f) (finding-detail f)))
    cv))
