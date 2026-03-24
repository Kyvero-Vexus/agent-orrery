;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-evidence-bundle-notarizer-tests.lisp — Tests for T1-T6 evidence bundle notarizer
;;; Bead: agent-orrery-xmsd

(in-package #:orrery/harness-tests)

(define-test tui-evidence-bundle-notarizer-suite)

(defun %mk-notar-dir (prefix)
  (let ((d (format nil "/tmp/orrery-notar-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %cleanup-notar (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

;; Empty dir => all rejected => pass=false
(define-test (tui-evidence-bundle-notarizer-suite empty-dir-all-rejected)
  (let* ((d (%mk-notar-dir "empty"))
         (b (orrery/adapter:notarize-tui-evidence-bundle
             d orrery/adapter:*mcp-tui-deterministic-command*)))
    (unwind-protect
         (progn
           (false (orrery/adapter:tbn-pass-p b))
           (is = 6 (orrery/adapter:tbn-rejected-count b))
           (is = 0 (orrery/adapter:tbn-notarized-count b)))
      (%cleanup-notar d))))

;; Wrong command => reject codes contain CMD_DRIFT
(define-test (tui-evidence-bundle-notarizer-suite wrong-command-drift-code)
  (let* ((d (%mk-notar-dir "drift"))
         (b (orrery/adapter:notarize-tui-evidence-bundle d "wrong-cmd"))
         (rec (first (orrery/adapter:tbn-records b))))
    (unwind-protect
         (true (find-if (lambda (c) (search "CMD_DRIFT" c))
                        (orrery/adapter:tnr-reject-codes rec)))
      (%cleanup-notar d))))

;; JSON fields present
(define-test (tui-evidence-bundle-notarizer-suite json-fields)
  (let* ((d (%mk-notar-dir "json"))
         (b (orrery/adapter:notarize-tui-evidence-bundle
             d orrery/adapter:*mcp-tui-deterministic-command*))
         (json (orrery/adapter:tui-bundle-notarization->json b)))
    (unwind-protect
         (progn
           (true (search "\"pass\":" json))
           (true (search "\"bundle_id\":" json))
           (true (search "\"command_hash\":" json))
           (true (search "\"notarized_count\":" json))
           (true (search "\"records\":" json))
           (true (search "\"notarization_id\":" json)))
      (%cleanup-notar d))))

;; Struct accessors
(define-test (tui-evidence-bundle-notarizer-suite record-struct)
  (let ((r (orrery/adapter:build-tui-notarization-record
            "T2" orrery/adapter:*mcp-tui-deterministic-command*
            "tx-digest" "art-digest" "/tmp/")))
    (is string= "T2" (orrery/adapter:tnr-scenario-id r))
    (true (orrery/adapter:tnr-notarized-p r))
    (true (plusp (length (orrery/adapter:tnr-notarization-id r))))))

;; Canonical command hash in bundle
(define-test (tui-evidence-bundle-notarizer-suite canonical-hash-in-bundle)
  (let* ((d (%mk-notar-dir "hash"))
         (b (orrery/adapter:notarize-tui-evidence-bundle
             d orrery/adapter:*mcp-tui-deterministic-command*)))
    (unwind-protect
         (is = (orrery/adapter:command-fingerprint orrery/adapter:*mcp-tui-deterministic-command*)
             (orrery/adapter:tbn-command-hash b))
      (%cleanup-notar d))))
