;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic-closure-gate.lisp — Cross-UI Epic 3/4 closure gate
;;; Bead: agent-orrery-i9p

(in-package #:orrery/adapter)

(defstruct (epic-closure-gate-result (:conc-name ecgr-))
  (epic3-pass-p nil :type boolean)
  (epic4-pass-p nil :type boolean)
  (overall-pass-p nil :type boolean)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string string string) (values epic-closure-gate-result &optional))
        evaluate-epic34-closure-gate)
 (ftype (function (epic-closure-gate-result) (values string &optional))
        epic-closure-gate-result->json))

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
         (overall (and epic3-ok epic4-ok)))
    (make-epic-closure-gate-result
     :epic3-pass-p epic3-ok
     :epic4-pass-p epic4-ok
     :overall-pass-p overall
     :detail (format nil "epic3=~A epic4=~A lock=~A notarized=~A web_cov=~D/~D tui_cov=~D/~D"
                     epic3-ok epic4-ok (pel-pass-p web-lock) (mtan-pass-p tui-note)
                     (ecr-required-scenarios-covered web-report)
                     (ecr-required-scenarios-total web-report)
                     (ecr-required-scenarios-covered tui-report)
                     (ecr-required-scenarios-total tui-report))
     :timestamp (get-universal-time))))

(defun epic-closure-gate-result->json (result)
  (declare (type epic-closure-gate-result result))
  (format nil
          "{\"epic3_pass\":~A,\"epic4_pass\":~A,\"overall_pass\":~A,\"detail\":\"~A\",\"timestamp\":~D}"
          (if (ecgr-epic3-pass-p result) "true" "false")
          (if (ecgr-epic4-pass-p result) "true" "false")
          (if (ecgr-overall-pass-p result) "true" "false")
          (ecgr-detail result)
          (ecgr-timestamp result)))
