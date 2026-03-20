;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; protocol-evidence-matrix.lisp — Epic 11 protocol/evidence version matrix CLI core
;;; Bead: agent-orrery-i944

(in-package #:orrery/adapter)

(deftype protocol-epic-key ()
  '(member :epic3 :epic4))

(defstruct (protocol-matrix-row
             (:constructor make-protocol-matrix-row
                 (&key epic protocol-version evidence-version deterministic-command
                       required-scenarios required-artifacts policy-note))
             (:conc-name pmr-))
  (epic :epic3 :type protocol-epic-key)
  (protocol-version "v1" :type string)
  (evidence-version "v1" :type string)
  (deterministic-command "" :type string)
  (required-scenarios '() :type list)
  (required-artifacts '() :type list)
  (policy-note "" :type string))

(defstruct (protocol-matrix-report
             (:constructor make-protocol-matrix-report
                 (&key rows epic3-pass-p epic4-pass-p overall-pass-p detail timestamp))
             (:conc-name pmrep-))
  (rows '() :type list)
  (epic3-pass-p nil :type boolean)
  (epic4-pass-p nil :type boolean)
  (overall-pass-p nil :type boolean)
  (detail "" :type string)
  (timestamp 0 :type integer))

(defparameter *protocol-evidence-version* "v1")
(defparameter *protocol-spec-version* "ep11-v1")

(declaim
 (ftype (function () (values list &optional)) build-protocol-evidence-matrix)
 (ftype (function (string string string string) (values protocol-matrix-report &optional))
        evaluate-protocol-evidence-matrix)
 (ftype (function (protocol-matrix-row) (values string &optional))
        protocol-matrix-row->json)
 (ftype (function (protocol-matrix-report) (values string &optional))
        protocol-matrix-report->json))

(defun build-protocol-evidence-matrix ()
  (list
   (make-protocol-matrix-row
    :epic :epic3
    :protocol-version *protocol-spec-version*
    :evidence-version *protocol-evidence-version*
    :deterministic-command *expected-tui-command*
    :required-scenarios (copy-list *default-tui-scenarios*)
    :required-artifacts '(:screenshot :transcript :machine-report :asciicast)
    :policy-note "Epic 3 closure requires mcp-tui-driver T1-T6 artifacts plus deterministic command evidence.")
   (make-protocol-matrix-row
    :epic :epic4
    :protocol-version *protocol-spec-version*
    :evidence-version *protocol-evidence-version*
    :deterministic-command *expected-web-command*
    :required-scenarios (copy-list *default-web-scenarios*)
    :required-artifacts '(:screenshot :trace :machine-report)
    :policy-note "Epic 4 closure requires Playwright S1-S6 screenshot+trace artifacts plus deterministic command evidence.")))

(defun %json-escape (s)
  (declare (type string s))
  (with-output-to-string (out)
    (loop for ch across s do
      (case ch
        (#\\ (write-string "\\\\" out))
        (#\" (write-string "\\\"" out))
        (#\Newline (write-string "\\n" out))
        (t (write-char ch out))))))

(defun %json-string (s)
  (declare (type string s))
  (format nil "\"~A\"" (%json-escape s)))

(defun protocol-matrix-row->json (row)
  (declare (type protocol-matrix-row row)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"epic\":" s)
    (write-string (%json-string (string-downcase (symbol-name (pmr-epic row)))) s)
    (write-string ",\"protocol_version\":" s)
    (write-string (%json-string (pmr-protocol-version row)) s)
    (write-string ",\"evidence_version\":" s)
    (write-string (%json-string (pmr-evidence-version row)) s)
    (write-string ",\"deterministic_command\":" s)
    (write-string (%json-string (pmr-deterministic-command row)) s)
    (write-string ",\"required_scenarios\":[" s)
    (loop for sid in (pmr-required-scenarios row)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string sid) s))
    (write-string "],\"required_artifacts\":[" s)
    (loop for kind in (pmr-required-artifacts row)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string (string-downcase (symbol-name kind))) s))
    (write-string "],\"policy_note\":" s)
    (write-string (%json-string (pmr-policy-note row)) s)
    (write-string "}" s)))

(defun evaluate-protocol-evidence-matrix (web-artifacts-dir web-command tui-artifacts-dir tui-command)
  (declare (type string web-artifacts-dir web-command tui-artifacts-dir tui-command)
           (optimize (safety 3)))
  (let* ((rows (build-protocol-evidence-matrix))
         (closure (evaluate-epic34-closure-gate web-artifacts-dir web-command tui-artifacts-dir tui-command))
         (epic3-ok (ecgr-epic3-pass-p closure))
         (epic4-ok (ecgr-epic4-pass-p closure))
         (overall (and epic3-ok epic4-ok)))
    (make-protocol-matrix-report
     :rows rows
     :epic3-pass-p epic3-ok
     :epic4-pass-p epic4-ok
     :overall-pass-p overall
     :detail (if overall
                 "Protocol/evidence matrix checks passed for Epic 3 and Epic 4."
                 "Protocol/evidence matrix denied closure: missing mandatory Epic 3 or Epic 4 evidence.")
     :timestamp (get-universal-time))))

(defun protocol-matrix-report->json (report)
  (declare (type protocol-matrix-report report)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"protocol_spec_version\":" s)
    (write-string (%json-string *protocol-spec-version*) s)
    (write-string ",\"evidence_schema_version\":" s)
    (write-string (%json-string *protocol-evidence-version*) s)
    (write-string ",\"epic3_pass\":" s)
    (write-string (if (pmrep-epic3-pass-p report) "true" "false") s)
    (write-string ",\"epic4_pass\":" s)
    (write-string (if (pmrep-epic4-pass-p report) "true" "false") s)
    (write-string ",\"overall_pass\":" s)
    (write-string (if (pmrep-overall-pass-p report) "true" "false") s)
    (write-string ",\"detail\":" s)
    (write-string (%json-string (pmrep-detail report)) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (pmrep-timestamp report))
    (write-string ",\"rows\":[" s)
    (loop for row in (pmrep-rows report)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (protocol-matrix-row->json row) s))
    (write-string "]}" s)))
