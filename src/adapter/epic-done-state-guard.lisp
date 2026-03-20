;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic-done-state-guard.lisp — reject Epic 3/4 done-state claims without evidence
;;; Bead: agent-orrery-t5i, agent-orrery-o2yx

(in-package #:orrery/adapter)

(defstruct (epic-done-state-result (:conc-name edr-))
  (epic-target :epic3 :type keyword)
  (done-claim-p nil :type boolean)
  (evidence-pass-p nil :type boolean)
  (allowed-p nil :type boolean)
  (blockers '() :type list)
  (remediation-commands '() :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (keyword boolean string string) (values epic-done-state-result &optional))
        evaluate-epic-done-state-guard)
 (ftype (function (epic-done-state-result) (values string &optional))
        epic-done-state-result->json))

(defun %json-escape-edr (s)
  (declare (type string s))
  (with-output-to-string (out)
    (loop for ch across s do
      (case ch
        (#\\ (write-string "\\\\" out))
        (#\" (write-string "\\\"" out))
        (#\Newline (write-string "\\n" out))
        (t (write-char ch out))))))

(defun %json-string-edr (s)
  (declare (type string s))
  (format nil "\"~A\"" (%json-escape-edr s)))

(defun evaluate-epic-done-state-guard (epic-target done-claim-p artifacts-dir command)
  "Deny done-state claims unless target evidence is valid.
EPIC-TARGET: :EPIC3 or :EPIC4
DONE-CLAIM-P: T means caller is attempting completion/reporting."
  (declare (type keyword epic-target)
           (type boolean done-claim-p)
           (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((evidence-ok
           (ecase epic-target
             (:epic3 (let* ((m (compile-mcp-tui-evidence-manifest artifacts-dir command))
                            (r (verify-runner-evidence
                                m
                                *default-tui-scenarios*
                                *tui-required-artifacts*
                                '(:machine-report :asciicast)
                                *expected-tui-command*)))
                       (ecr-pass-p r)))
             (:epic4 (let* ((m (compile-playwright-evidence-manifest artifacts-dir command))
                            (r (verify-runner-evidence
                                m
                                *default-web-scenarios*
                                *web-required-artifacts*
                                '(:machine-report)
                                *expected-web-command*)))
                       (ecr-pass-p r)))))
         (allowed (if done-claim-p evidence-ok t))
         (blockers '())
         (remediation '()))
    (when (and done-claim-p (not evidence-ok))
      (ecase epic-target
        (:epic3
         (push "epic3-mcp-tui-driver-t1-t6-evidence-missing" blockers)
         (push *expected-tui-command* remediation))
        (:epic4
         (push "epic4-playwright-s1-s6-evidence-missing" blockers)
         (push *expected-web-command* remediation))))
    (make-epic-done-state-result
     :epic-target epic-target
     :done-claim-p done-claim-p
     :evidence-pass-p evidence-ok
     :allowed-p allowed
     :blockers (nreverse blockers)
     :remediation-commands (nreverse remediation)
     :detail (format nil "target=~A claim=~A evidence=~A" epic-target done-claim-p evidence-ok)
     :timestamp (get-universal-time))))

(defun epic-done-state-result->json (res)
  (declare (type epic-done-state-result res)
           (optimize (safety 3)))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"target\":" s)
    (write-string (%json-string-edr (string-downcase (symbol-name (edr-epic-target res)))) s)
    (write-string ",\"done_claim\":" s)
    (write-string (if (edr-done-claim-p res) "true" "false") s)
    (write-string ",\"evidence_pass\":" s)
    (write-string (if (edr-evidence-pass-p res) "true" "false") s)
    (write-string ",\"allowed\":" s)
    (write-string (if (edr-allowed-p res) "true" "false") s)
    (write-string ",\"blockers\":[" s)
    (loop for blocker in (edr-blockers res)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string-edr blocker) s))
    (write-string "],\"remediation_commands\":[" s)
    (loop for cmd in (edr-remediation-commands res)
          for i fixnum from 0 do
            (when (> i 0) (write-char #\, s))
            (write-string (%json-string-edr cmd) s))
    (write-string "],\"detail\":" s)
    (write-string (%json-string-edr (edr-detail res)) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (edr-timestamp res))
    (write-string "}" s)))
