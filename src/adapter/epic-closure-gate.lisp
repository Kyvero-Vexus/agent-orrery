;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic-closure-gate.lisp — Cross-UI Epic 3/4 closure gate
;;; Bead: agent-orrery-i9p, agent-orrery-o2yx

(in-package #:orrery/adapter)

(defstruct (epic-closure-gate-result (:conc-name ecgr-))
  (epic3-pass-p nil :type boolean)
  (epic4-pass-p nil :type boolean)
  (overall-pass-p nil :type boolean)
  (blockers '() :type list)
  (remediation-commands '() :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string string string) (values epic-closure-gate-result &optional))
        evaluate-epic34-closure-gate)
 (ftype (function (epic-closure-gate-result) (values string &optional))
        epic-closure-gate-result->json))

(defun %json-escape-ecgr (s)
  (declare (type string s))
  (with-output-to-string (out)
    (loop for ch across s do
      (case ch
        (#\\ (write-string "\\\\" out))
        (#\" (write-string "\\\"" out))
        (#\Newline (write-string "\\n" out))
        (t (write-char ch out))))))

(defun %json-string-ecgr (s)
  (declare (type string s))
  (format nil "\"~A\"" (%json-escape-ecgr s)))

(defun evaluate-epic34-closure-gate (web-artifacts-dir web-command tui-artifacts-dir tui-command)
  "Validate Epic 3/4 closure evidence requirements.
Epic 4: Playwright S1-S6 screenshot+trace + deterministic command.
Epic 3: mcp-tui-driver T1-T6 screenshot+transcript + machine-report/asciicast + deterministic command."
  (declare (type string web-artifacts-dir web-command tui-artifacts-dir tui-command)
           (optimize (safety 3)))
  (let* ((web-manifest (compile-playwright-evidence-manifest web-artifacts-dir web-command))
         (tui-manifest (compile-mcp-tui-evidence-manifest tui-artifacts-dir tui-command))
         (web-report (verify-runner-evidence
                      web-manifest
                      *default-web-scenarios*
                      *web-required-artifacts*
                      '(:machine-report)
                      *expected-web-command*))
         (web-lock (build-playwright-evidence-lock web-artifacts-dir web-command))
         (tui-report (verify-runner-evidence
                      tui-manifest
                      *default-tui-scenarios*
                      *tui-required-artifacts*
                      '(:machine-report :asciicast)
                      *expected-tui-command*))
         (tui-note (notarize-mcp-tui-artifacts tui-artifacts-dir tui-command tui-artifacts-dir))
         (epic4-ok (and (ecr-pass-p web-report)
                        (pel-pass-p web-lock)))
         (epic3-ok (and (ecr-pass-p tui-report)
                        (mtan-pass-p tui-note)))
         (overall (and epic3-ok epic4-ok))
         (blockers '())
         (remediation '()))
    (unless epic3-ok
      (push "epic3-mcp-tui-driver-t1-t6-evidence-missing" blockers)
      (push *expected-tui-command* remediation))
    (unless epic4-ok
      (push "epic4-playwright-s1-s6-evidence-missing" blockers)
      (push *expected-web-command* remediation))
    (make-epic-closure-gate-result
     :epic3-pass-p epic3-ok
     :epic4-pass-p epic4-ok
     :overall-pass-p overall
     :blockers (nreverse blockers)
     :remediation-commands (nreverse remediation)
     :detail (format nil "epic3=~A epic4=~A lock=~A notarized=~A web_cov=~D/~D tui_cov=~D/~D"
                     epic3-ok epic4-ok (pel-pass-p web-lock) (mtan-pass-p tui-note)
                     (ecr-required-scenarios-covered web-report)
                     (ecr-required-scenarios-total web-report)
                     (ecr-required-scenarios-covered tui-report)
                     (ecr-required-scenarios-total tui-report))
     :timestamp (get-universal-time))))

(defun epic-closure-gate-result->json (result)
  (declare (type epic-closure-gate-result result)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"epic3_pass\":" s)
    (write-string (if (ecgr-epic3-pass-p result) "true" "false") s)
    (write-string ",\"epic4_pass\":" s)
    (write-string (if (ecgr-epic4-pass-p result) "true" "false") s)
    (write-string ",\"overall_pass\":" s)
    (write-string (if (ecgr-overall-pass-p result) "true" "false") s)
    (write-string ",\"blockers\":[" s)
    (loop for blocker in (ecgr-blockers result)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string-ecgr blocker) s))
    (write-string "],\"remediation_commands\":[" s)
    (loop for cmd in (ecgr-remediation-commands result)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string-ecgr cmd) s))
    (write-string "],\"detail\":" s)
    (write-string (%json-string-ecgr (ecgr-detail result)) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (ecgr-timestamp result))
    (write-string "}" s)))
