;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; evidence-recertification-gate.lisp — release-branch Epic 3/4 evidence recertifier
;;; Bead: agent-orrery-f15

(in-package #:orrery/adapter)

(defstruct (evidence-recertification-result (:conc-name err-))
  (stored-pass-p nil :type boolean)
  (regenerated-pass-p nil :type boolean)
  (parity-pass-p nil :type boolean)
  (overall-pass-p nil :type boolean)
  (blockers nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string string string string string) (values evidence-recertification-result &optional))
        evaluate-evidence-recertification-gate)
 (ftype (function (evidence-recertification-result) (values string &optional))
        evidence-recertification-result->json))

(defun %scenario-status-map (manifest required-ids infer-fn)
  (declare (type list required-ids))
  (let ((table (make-hash-table :test #'equal)))
    (dolist (sid required-ids)
      (setf (gethash sid table) :missing))
    (dolist (a (rem-artifacts manifest))
      (let ((sid (funcall infer-fn (file-namestring (ea-path a)))))
        (when sid
          (setf (gethash sid table) :present))))
    table))

(defun %maps-equal-p (a b ids)
  (every (lambda (sid) (eq (gethash sid a) (gethash sid b))) ids))

(defun evaluate-evidence-recertification-gate (web-stored-dir web-regen-dir tui-stored-dir tui-regen-dir web-command tui-command)
  "Re-verify stored and regenerated evidence before release tagging.
Deny if either set fails Epic 3/4 closure gate, or if stored/regenerated scenario presence diverges." 
  (declare (type string web-stored-dir web-regen-dir tui-stored-dir tui-regen-dir web-command tui-command)
           (optimize (safety 3)))
  (let* ((stored (evaluate-epic34-closure-gate web-stored-dir web-command tui-stored-dir tui-command))
         (regen (evaluate-epic34-closure-gate web-regen-dir web-command tui-regen-dir tui-command))
         (web-stored (compile-playwright-evidence-manifest web-stored-dir web-command))
         (web-regen (compile-playwright-evidence-manifest web-regen-dir web-command))
         (tui-stored (compile-mcp-tui-evidence-manifest tui-stored-dir tui-command))
         (tui-regen (compile-mcp-tui-evidence-manifest tui-regen-dir tui-command))
         (web-map-stored (%scenario-status-map web-stored *default-web-scenarios* #'infer-playwright-scenario-id))
         (web-map-regen (%scenario-status-map web-regen *default-web-scenarios* #'infer-playwright-scenario-id))
         (tui-map-stored (%scenario-status-map tui-stored *default-tui-scenarios* #'infer-mcp-tui-scenario-id))
         (tui-map-regen (%scenario-status-map tui-regen *default-tui-scenarios* #'infer-mcp-tui-scenario-id))
         (parity-ok (and (%maps-equal-p web-map-stored web-map-regen *default-web-scenarios*)
                         (%maps-equal-p tui-map-stored tui-map-regen *default-tui-scenarios*)))
         (stored-ok (ecgr-overall-pass-p stored))
         (regen-ok (ecgr-overall-pass-p regen))
         (blockers nil))
    (unless stored-ok (push "stored-evidence-fails-closure-gate" blockers))
    (unless regen-ok (push "regenerated-evidence-fails-closure-gate" blockers))
    (unless parity-ok (push "stored-vs-regenerated-evidence-mismatch" blockers))
    (let* ((normalized-blockers (nreverse blockers))
           (overall (and stored-ok regen-ok parity-ok)))
      (make-evidence-recertification-result
       :stored-pass-p stored-ok
       :regenerated-pass-p regen-ok
       :parity-pass-p parity-ok
       :overall-pass-p overall
       :blockers normalized-blockers
       :detail (format nil "stored=~A regen=~A parity=~A blockers=~D"
                       stored-ok regen-ok parity-ok (length normalized-blockers))
       :timestamp (get-universal-time)))))

(defun evidence-recertification-result->json (result)
  (declare (type evidence-recertification-result result))
  (format nil
          "{\"stored_pass\":~A,\"regenerated_pass\":~A,\"parity_pass\":~A,\"overall_pass\":~A,\"blocker_count\":~D,\"detail\":\"~A\",\"timestamp\":~D}"
          (if (err-stored-pass-p result) "true" "false")
          (if (err-regenerated-pass-p result) "true" "false")
          (if (err-parity-pass-p result) "true" "false")
          (if (err-overall-pass-p result) "true" "false")
          (length (err-blockers result))
          (err-detail result)
          (err-timestamp result)))
