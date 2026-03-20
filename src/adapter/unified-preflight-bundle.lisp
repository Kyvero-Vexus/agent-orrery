;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; unified-preflight-bundle.lisp — deterministic Epic3/4 preflight bundle emitter
;;; Bead: agent-orrery-pk7y

(in-package #:orrery/adapter)

(defstruct (unified-preflight-bundle
             (:constructor make-unified-preflight-bundle
                 (&key closure matrix gaps overall-pass-p detail timestamp))
             (:conc-name upb-))
  (closure nil :type epic-closure-gate-result)
  (matrix nil :type protocol-matrix-report)
  (gaps nil :type protocol-evidence-gap-report)
  (overall-pass-p nil :type boolean)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string string string string) (values unified-preflight-bundle &optional))
        evaluate-unified-preflight-bundle)
 (ftype (function (unified-preflight-bundle) (values string &optional))
        unified-preflight-bundle->json))

(defun evaluate-unified-preflight-bundle (web-artifacts-dir web-command tui-artifacts-dir tui-command)
  (declare (type string web-artifacts-dir web-command tui-artifacts-dir tui-command)
           (optimize (safety 3)))
  (let* ((closure (evaluate-epic34-closure-gate web-artifacts-dir web-command tui-artifacts-dir tui-command))
         (matrix (evaluate-protocol-evidence-matrix web-artifacts-dir web-command tui-artifacts-dir tui-command))
         (gaps (explain-protocol-evidence-gaps web-artifacts-dir web-command tui-artifacts-dir tui-command))
         (overall (and (ecgr-overall-pass-p closure)
                       (pmrep-overall-pass-p matrix)
                       (pegr-closure-pass-p gaps)
                       (pegr-matrix-pass-p gaps))))
    (make-unified-preflight-bundle
     :closure closure
     :matrix matrix
     :gaps gaps
     :overall-pass-p overall
     :detail (if overall
                 "Unified preflight bundle passed: closure gate, protocol matrix, and evidence gaps all satisfied."
                 "Unified preflight bundle failed: Epic 3/4 evidence policy denies closure until required framework evidence is complete.")
     :timestamp (get-universal-time))))

(defun unified-preflight-bundle->json (bundle)
  (declare (type unified-preflight-bundle bundle)
           (optimize (safety 3)))
  ;; Stable field ordering is intentional for deterministic CI artifacts.
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"schema\":\"ep11-preflight-bundle-v1\"" s)
    (write-string ",\"overall_pass\":" s)
    (write-string (if (upb-overall-pass-p bundle) "true" "false") s)
    (write-string ",\"detail\":" s)
    (write-string (%json-string-ecgr (upb-detail bundle)) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (upb-timestamp bundle))
    (write-string ",\"closure_gate\":" s)
    (write-string (epic-closure-gate-result->json (upb-closure bundle)) s)
    (write-string ",\"protocol_matrix\":" s)
    (write-string (protocol-matrix-report->json (upb-matrix bundle)) s)
    (write-string ",\"evidence_gaps\":" s)
    (write-string (protocol-evidence-gap-report->json (upb-gaps bundle)) s)
    (write-string "}" s)))
