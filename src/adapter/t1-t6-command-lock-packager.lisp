;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-command-lock-packager.lisp — deterministic command-lock + rerun packager for T1-T6
;;; Bead: agent-orrery-1vnv

(in-package #:orrery/adapter)

;; ─── Command-lock ADT ────────────────────────────────────────────────────────

(defstruct (t1-t6-command-lock (:conc-name cmdlock-))
  "Locked, verifiable command identity for a T1-T6 replay run."
  (command *canonical-t1-t6-command* :type string)
  (fingerprint "" :type string)        ; sxhash of command string
  (locked-at "" :type string)
  (canonical-p nil :type boolean))

(defstruct (t1-t6-rerun-pack (:conc-name pack-))
  "Reproducible rerun pack: command-lock + per-scenario artifact fingerprints."
  (command-lock nil :type (or null t1-t6-command-lock))
  (journal nil :type (or null t1-t6-replay-journal))
  (pack-hash "" :type string)
  (assembled-at "" :type string)
  (verdict :missing :type (member :complete :incomplete :missing)))

;; ─── Constructors ─────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string) (values t1-t6-command-lock &optional)) lock-command)
 (ftype (function (t1-t6-command-lock) (values boolean &optional)) command-lock-valid-p)
 (ftype (function (t1-t6-replay-journal) (values t1-t6-rerun-pack &optional)) assemble-rerun-pack)
 (ftype (function (t1-t6-rerun-pack) (values string &optional)) rerun-pack->json)
 (ftype (function (string) (values string &optional)) hash-string))

(defun hash-string (s)
  (declare (type string s))
  (format nil "~X" (sxhash s)))

(defun lock-command (cmd)
  "Lock a command string, marking whether it is canonical."
  (declare (type string cmd))
  (make-t1-t6-command-lock
   :command cmd
   :fingerprint (hash-string cmd)
   :locked-at (format nil "~A" (get-universal-time))
   :canonical-p (canonical-command-p cmd)))

(defun command-lock-valid-p (lock)
  "Return T iff the lock's fingerprint matches its command and it is canonical."
  (declare (type t1-t6-command-lock lock))
  (and (cmdlock-canonical-p lock)
       (string= (cmdlock-fingerprint lock) (hash-string (cmdlock-command lock)))))

;; ─── Pack assembly ────────────────────────────────────────────────────────────

(defun assemble-rerun-pack (journal)
  "Assemble a reproducible rerun pack from a T1-T6 replay journal."
  (declare (type t1-t6-replay-journal journal))
  (let* ((cmd (journal-deterministic-command journal))
         (lock (lock-command cmd))
         (verdict (if (journal-complete-p journal) :complete
                      (if (null (journal-rows journal)) :missing :incomplete)))
         (pack-content (format nil "~A:~A" cmd (journal-created-at journal)))
         (pack-hash (hash-string pack-content)))
    (unless (canonical-command-p cmd)
      (error "RERUN-PACK: journal command ~S is not canonical; refusing to assemble pack" cmd))
    (make-t1-t6-rerun-pack
     :command-lock lock
     :journal journal
     :pack-hash pack-hash
     :assembled-at (format nil "~A" (get-universal-time))
     :verdict verdict)))

;; ─── Serialization ────────────────────────────────────────────────────────────

(defun rerun-pack->json (pack)
  "Serialize a rerun pack to JSON string."
  (declare (type t1-t6-rerun-pack pack))
  (let ((lock (pack-command-lock pack))
        (journal (pack-journal pack)))
    (format nil
            "{\"command\":\"~A\",\"command_fingerprint\":\"~A\",\"canonical\":~A,\"pack_hash\":\"~A\",\"verdict\":\"~A\",\"assembled_at\":\"~A\",\"journal_complete\":~A,\"missing_scenarios\":[~{\"~A\"~^,~}]}"
            (if lock (cmdlock-command lock) *canonical-t1-t6-command*)
            (if lock (cmdlock-fingerprint lock) "")
            (if (and lock (cmdlock-canonical-p lock)) "true" "false")
            (pack-pack-hash pack)
            (string (pack-verdict pack))
            (pack-assembled-at pack)
            (if (and journal (journal-complete-p journal)) "true" "false")
            (if journal
                (mapcar #'string (journal-missing-scenarios journal))
                '("T1" "T2" "T3" "T4" "T5" "T6")))))

;; ─── CLI entry point ──────────────────────────────────────────────────────────

(defun build-and-emit-rerun-pack (output-path)
  "Build an empty rerun-pack (no evidence yet) and write JSON to OUTPUT-PATH.
   This is the fail-closed bootstrap path: all scenarios missing by default."
  (declare (type string output-path))
  (let* ((journal (make-empty-journal))
         (pack (assemble-rerun-pack journal))
         (json (rerun-pack->json pack)))
    (with-open-file (s output-path :direction :output :if-exists :supersede)
      (write-string json s))
    (format t "Rerun pack written to ~A~%" output-path)
    (format t "Verdict: ~A~%" (pack-verdict pack))
    (format t "Command: ~A~%" *canonical-t1-t6-command*)
    pack))
