;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-replay-journal.lisp — Typed T1-T6 replay-journal ADTs + serializer contracts
;;; Bead: agent-orrery-vg10

(in-package #:orrery/adapter)

;; ─── ADT types ───────────────────────────────────────────────────────────────

(deftype replay-journal-scenario-id ()
  '(member :T1 :T2 :T3 :T4 :T5 :T6))

(defstruct (replay-command-fingerprint (:conc-name rcf-))
  "Locked deterministic command identity for one replay run."
  (canonical "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" :type string)
  (hash "" :type string)
  (timestamp "" :type string))

(defstruct (replay-transcript-digest (:conc-name rtd-))
  "Digest of a T1-T6 scenario transcript timeline entry."
  (scenario-id :T1 :type replay-journal-scenario-id)
  (digest "" :type string)
  (line-count 0 :type fixnum)
  (captured-at "" :type string))

(defstruct (replay-artifact-bundle-ref (:conc-name rabr-))
  "Reference to an artifact bundle for a given T1-T6 scenario."
  (scenario-id :T1 :type replay-journal-scenario-id)
  (artifact-paths nil :type list)  ; list of strings
  (bundle-hash "" :type string)
  (base-dir "test-results/tui-artifacts/" :type string))

(defstruct (t1-t6-replay-journal-row (:conc-name jrow-))
  "One row in the T1-T6 replay journal (per scenario)."
  (scenario-id :T1 :type replay-journal-scenario-id)
  (command-fingerprint nil :type (or null replay-command-fingerprint))
  (transcript-digest nil :type (or null replay-transcript-digest))
  (artifact-bundle nil :type (or null replay-artifact-bundle-ref))
  (verdict :missing :type (member :pass :fail :missing)))

(defstruct (t1-t6-replay-journal (:conc-name journal-))
  "Full T1-T6 replay journal — six rows, one per scenario."
  (rows nil :type list)  ; list of t1-t6-replay-journal-row
  (created-at "" :type string)
  (deterministic-command "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" :type string))

;; ─── Canonical command enforcement ───────────────────────────────────────────

(defparameter *canonical-t1-t6-command* "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
  "The one true deterministic command for mcp-tui-driver T1-T6 runs.")

(declaim
 (ftype (function (string) (values boolean &optional)) canonical-command-p)
 (ftype (function () (values t1-t6-replay-journal &optional)) make-empty-journal)
 (ftype (function (t1-t6-replay-journal) (values boolean &optional)) journal-complete-p)
 (ftype (function (t1-t6-replay-journal) (values list &optional)) journal-missing-scenarios)
 (ftype (function (t1-t6-replay-journal) (values string &optional)) journal->json)
 (ftype (function (string) (values (or null t1-t6-replay-journal) &optional)) json->journal))

(defun canonical-command-p (cmd)
  (declare (type string cmd))
  (string= cmd *canonical-t1-t6-command*))

(defun make-empty-journal ()
  "Create a blank T1-T6 replay journal with all scenarios in :missing state."
  (make-t1-t6-replay-journal
   :rows (mapcar (lambda (id)
                   (make-t1-t6-replay-journal-row :scenario-id id :verdict :missing))
                 '(:T1 :T2 :T3 :T4 :T5 :T6))
   :created-at (format nil "~A" (get-universal-time))
   :deterministic-command *canonical-t1-t6-command*))

(defun journal-complete-p (journal)
  "Return T if all six scenarios have :pass verdict."
  (declare (type t1-t6-replay-journal journal))
  (every (lambda (row) (eq (jrow-verdict row) :pass))
         (journal-rows journal)))

(defun journal-missing-scenarios (journal)
  "Return list of scenario-ids that are not :pass."
  (declare (type t1-t6-replay-journal journal))
  (mapcar #'jrow-scenario-id
          (remove-if (lambda (row) (eq (jrow-verdict row) :pass))
                     (journal-rows journal))))

;; ─── Serialization ────────────────────────────────────────────────────────────

(defun row->alist (row)
  (declare (type t1-t6-replay-journal-row row))
  (let ((cf (jrow-command-fingerprint row))
        (td (jrow-transcript-digest row))
        (ab (jrow-artifact-bundle row)))
    `(("scenario_id" . ,(string (jrow-scenario-id row)))
      ("verdict"     . ,(string (jrow-verdict row)))
      ("command_hash" . ,(if cf (rcf-hash cf) ""))
      ("command_canonical" . ,(if cf (rcf-canonical cf) *canonical-t1-t6-command*))
      ("transcript_digest" . ,(if td (rtd-digest td) ""))
      ("transcript_lines"  . ,(if td (rtd-line-count td) 0))
      ("artifact_paths"    . ,(if ab (rabr-artifact-paths ab) nil))
      ("bundle_hash"       . ,(if ab (rabr-bundle-hash ab) "")))))

(defun journal->json (journal)
  "Serialize T1-T6 replay journal to a JSON string (no external deps)."
  (declare (type t1-t6-replay-journal journal))
  (let* ((rows-json
          (format nil "[~{~A~^,~}]"
                  (mapcar (lambda (row)
                            (let ((a (row->alist row)))
                              (format nil "{~{\"~A\":\"~A\"~^,~}}"
                                      (loop for (k . v) in a
                                            collect k
                                            collect (if (listp v)
                                                        (format nil "[~{\"~A\"~^,~}]" v)
                                                        v)))))
                          (journal-rows journal)))))
    (format nil "{\"deterministic_command\":\"~A\",\"created_at\":\"~A\",\"complete\":~A,\"rows\":~A}"
            (journal-deterministic-command journal)
            (journal-created-at journal)
            (if (journal-complete-p journal) "true" "false")
            rows-json)))

(defun journal->plist (journal)
  "Serialize to plist for CL consumers."
  (declare (type t1-t6-replay-journal journal))
  (list :deterministic-command (journal-deterministic-command journal)
        :created-at (journal-created-at journal)
        :complete (journal-complete-p journal)
        :missing-scenarios (journal-missing-scenarios journal)
        :rows (mapcar #'row->alist (journal-rows journal))))

;; ─── Fail-closed schema assertion ────────────────────────────────────────────

(defun assert-journal-schema (journal)
  "Signal an error if journal fails structural integrity."
  (declare (type t1-t6-replay-journal journal))
  (unless (canonical-command-p (journal-deterministic-command journal))
    (error "REPLAY-JOURNAL: non-canonical command ~S (expected ~S)"
           (journal-deterministic-command journal)
           *canonical-t1-t6-command*))
  (let ((ids (mapcar #'jrow-scenario-id (journal-rows journal))))
    (dolist (required '(:T1 :T2 :T3 :T4 :T5 :T6))
      (unless (member required ids)
        (error "REPLAY-JOURNAL: missing scenario ~S in journal rows" required))))
  journal)
