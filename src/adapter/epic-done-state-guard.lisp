;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic-done-state-guard.lisp — reject Epic 3/4 done-state claims without evidence
;;; Bead: agent-orrery-t5i

(in-package #:orrery/adapter)

(defstruct (epic-done-state-result (:conc-name edr-))
  (epic-target :epic3 :type keyword)
  (done-claim-p nil :type boolean)
  (evidence-pass-p nil :type boolean)
  (allowed-p nil :type boolean)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (keyword boolean string string) (values epic-done-state-result &optional))
        evaluate-epic-done-state-guard)
 (ftype (function (epic-done-state-result) (values string &optional))
        epic-done-state-result->json))

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
         (allowed (if done-claim-p evidence-ok t)))
    (make-epic-done-state-result
     :epic-target epic-target
     :done-claim-p done-claim-p
     :evidence-pass-p evidence-ok
     :allowed-p allowed
     :detail (format nil "target=~A claim=~A evidence=~A" epic-target done-claim-p evidence-ok)
     :timestamp (get-universal-time))))

(defun epic-done-state-result->json (res)
  (declare (type epic-done-state-result res))
  (format nil
          "{\"target\":\"~(~A~)\",\"done_claim\":~A,\"evidence_pass\":~A,\"allowed\":~A,\"detail\":\"~A\",\"timestamp\":~D}"
          (edr-epic-target res)
          (if (edr-done-claim-p res) "true" "false")
          (if (edr-evidence-pass-p res) "true" "false")
          (if (edr-allowed-p res) "true" "false")
          (edr-detail res)
          (edr-timestamp res)))
