;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-contract-matrix-tests.lisp — Tests for T1-T6 scenario contract matrix
;;; Bead: agent-orrery-b7v

(in-package #:orrery/harness-tests)

(define-test mcp-tui-contract-matrix-suite)

(defun %mk-tcm-dir (prefix)
  (let ((d (format nil "/tmp/orrery-tcm-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %cleanup-tcm (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

;; Matrix has 6 contracts (T1..T6)
(define-test (mcp-tui-contract-matrix-suite six-contracts)
  (let* ((d (%mk-tcm-dir "6c"))
         (m (orrery/adapter:compile-tui-contract-matrix d "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
    (unwind-protect
         (is = 6 (length (orrery/adapter:tcm-contracts m)))
      (%cleanup-tcm d))))

;; Each row has canonical command hash
(define-test (mcp-tui-contract-matrix-suite canonical-hash-in-rows)
  (let* ((d (%mk-tcm-dir "hash"))
         (m (orrery/adapter:compile-tui-contract-matrix
             d orrery/adapter:*mcp-tui-deterministic-command*)))
    (unwind-protect
         (let ((canon-hash (orrery/adapter:command-fingerprint orrery/adapter:*mcp-tui-deterministic-command*)))
           (dolist (c (orrery/adapter:tcm-contracts m))
             (is = canon-hash (orrery/adapter:tcr-command-hash c))))
      (%cleanup-tcm d))))

;; JSON fields present
(define-test (mcp-tui-contract-matrix-suite json-fields)
  (let* ((d (%mk-tcm-dir "json"))
         (m (orrery/adapter:compile-tui-contract-matrix d "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
         (json (orrery/adapter:tui-contract-matrix->json m)))
    (unwind-protect
         (progn
           (true (search "\"pass\":" json))
           (true (search "\"command_hash\":" json))
           (true (search "\"missing_count\":" json))
           (true (search "\"contracts\":" json))
           (true (search "\"required_artifacts\":" json))
           (true (search "\"T1\"" json)))
      (%cleanup-tcm d))))

;; Artifact index covers T1-T6 x artifact kinds
(define-test (mcp-tui-contract-matrix-suite artifact-index-coverage)
  (let* ((d (%mk-tcm-dir "idx"))
         (m (orrery/adapter:compile-tui-contract-matrix d "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
         (idx (orrery/adapter:contract-matrix->artifact-index m)))
    (unwind-protect
         (is = (* 6 (length orrery/adapter:*tui-required-artifact-kinds*))
             (length idx))
      (%cleanup-tcm d))))

;; Struct accessors work on contract row
(define-test (mcp-tui-contract-matrix-suite struct-accessors)
  (let ((c (orrery/adapter:build-tui-contract-row "T3")))
    (is string= "T3" (orrery/adapter:tcr-scenario-id c))
    (is string= orrery/adapter:*mcp-tui-deterministic-command*
        (orrery/adapter:tcr-command c))
    (true (not (null (orrery/adapter:tcr-required-artifacts c))))))
