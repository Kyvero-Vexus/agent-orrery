;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; protocol-evidence-gap-explainer.lisp — deterministic missing-evidence explainer + remediation emitter
;;; Bead: agent-orrery-fdtj

(in-package #:orrery/adapter)

(defstruct (protocol-remediation-step
             (:constructor make-protocol-remediation-step (&key epic command artifact-dir scenarios artifacts framework))
             (:conc-name prs-))
  (epic :epic3 :type protocol-epic-key)
  (framework "" :type string)
  (command "" :type string)
  (artifact-dir "" :type string)
  (scenarios '() :type list)
  (artifacts '() :type list))

(defstruct (protocol-evidence-gap-report
             (:constructor make-protocol-evidence-gap-report
                 (&key closure-pass-p matrix-pass-p gaps remediation detail timestamp))
             (:conc-name pegr-))
  (closure-pass-p nil :type boolean)
  (matrix-pass-p nil :type boolean)
  (gaps '() :type list)
  (remediation '() :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string string string) (values protocol-evidence-gap-report &optional))
        explain-protocol-evidence-gaps)
 (ftype (function (protocol-remediation-step) (values string &optional)) protocol-remediation-step->json)
 (ftype (function (protocol-evidence-gap-report) (values string &optional)) protocol-evidence-gap-report->json))

(defun %json-escape-fdtj (s)
  (declare (type string s))
  (with-output-to-string (out)
    (loop for ch across s do
      (case ch
        (#\\ (write-string "\\\\" out))
        (#\" (write-string "\\\"" out))
        (#\Newline (write-string "\\n" out))
        (t (write-char ch out))))))

(defun %json-string-fdtj (s)
  (declare (type string s))
  (format nil "\"~A\"" (%json-escape-fdtj s)))

(defun %step-for-epic (epic)
  (declare (type protocol-epic-key epic))
  (ecase epic
    (:epic3 (make-protocol-remediation-step
             :epic :epic3
             :framework "mcp-tui-driver"
             :command *expected-tui-command*
             :artifact-dir "test-results/tui-artifacts/"
             :scenarios (copy-list *default-tui-scenarios*)
             :artifacts '(:screenshot :transcript :machine-report :asciicast)))
    (:epic4 (make-protocol-remediation-step
             :epic :epic4
             :framework "Playwright"
             :command *expected-web-command*
             :artifact-dir "test-results/e2e-report/"
             :scenarios (copy-list *default-web-scenarios*)
             :artifacts '(:screenshot :trace :machine-report)))))

(defun explain-protocol-evidence-gaps (web-artifacts-dir web-command tui-artifacts-dir tui-command)
  (declare (type string web-artifacts-dir web-command tui-artifacts-dir tui-command)
           (optimize (safety 3)))
  (let* ((closure (evaluate-epic34-closure-gate web-artifacts-dir web-command tui-artifacts-dir tui-command))
         (matrix (evaluate-protocol-evidence-matrix web-artifacts-dir web-command tui-artifacts-dir tui-command))
         (gaps '())
         (remediation '()))
    (unless (ecgr-epic3-pass-p closure)
      (push "epic3-mcp-tui-driver-t1-t6-evidence-missing" gaps)
      (push (%step-for-epic :epic3) remediation))
    (unless (ecgr-epic4-pass-p closure)
      (push "epic4-playwright-s1-s6-evidence-missing" gaps)
      (push (%step-for-epic :epic4) remediation))
    (make-protocol-evidence-gap-report
     :closure-pass-p (ecgr-overall-pass-p closure)
     :matrix-pass-p (pmrep-overall-pass-p matrix)
     :gaps (nreverse gaps)
     :remediation (nreverse remediation)
     :detail (if (and (ecgr-overall-pass-p closure) (pmrep-overall-pass-p matrix))
                 "No evidence gaps. Epic 3/4 policy gates satisfied."
                 "Evidence gaps detected. Follow deterministic remediation commands; fail-closed until artifacts exist.")
     :timestamp (get-universal-time))))

(defun protocol-remediation-step->json (step)
  (declare (type protocol-remediation-step step)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"epic\":" s)
    (write-string (%json-string-fdtj (string-downcase (symbol-name (prs-epic step)))) s)
    (write-string ",\"framework\":" s)
    (write-string (%json-string-fdtj (prs-framework step)) s)
    (write-string ",\"command\":" s)
    (write-string (%json-string-fdtj (prs-command step)) s)
    (write-string ",\"artifact_dir\":" s)
    (write-string (%json-string-fdtj (prs-artifact-dir step)) s)
    (write-string ",\"scenarios\":[" s)
    (loop for sid in (prs-scenarios step)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string-fdtj sid) s))
    (write-string "],\"artifacts\":[" s)
    (loop for kind in (prs-artifacts step)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string-fdtj (string-downcase (symbol-name kind))) s))
    (write-string "]}" s)))

(defun protocol-evidence-gap-report->json (report)
  (declare (type protocol-evidence-gap-report report)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"closure_pass\":" s)
    (write-string (if (pegr-closure-pass-p report) "true" "false") s)
    (write-string ",\"matrix_pass\":" s)
    (write-string (if (pegr-matrix-pass-p report) "true" "false") s)
    (write-string ",\"detail\":" s)
    (write-string (%json-string-fdtj (pegr-detail report)) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (pegr-timestamp report))
    (write-string ",\"gaps\":[" s)
    (loop for g in (pegr-gaps report)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string-fdtj g) s))
    (write-string "],\"remediation\":[" s)
    (loop for step in (pegr-remediation report)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (protocol-remediation-step->json step) s))
    (write-string "]}" s)))
