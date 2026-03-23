;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-transcript-fingerprint-normalizer-tests.lisp — Tests for T1-T6 transcript fingerprint normalizer
;;; Bead: agent-orrery-309

(in-package #:orrery/harness-tests)

(define-test tui-transcript-fingerprint-normalizer-suite)

;; canonicalize-transcript-line strips trailing whitespace
(define-test (tui-transcript-fingerprint-normalizer-suite canonicalize-line)
  (is string= "hello" (orrery/adapter:canonicalize-transcript-line "hello   "))
  (is string= "hello" (orrery/adapter:canonicalize-transcript-line "hello	"))
  (is string= "hello" (orrery/adapter:canonicalize-transcript-line (format nil "hello~C" #\Return)))
  (is string= "" (orrery/adapter:canonicalize-transcript-line "")))

;; Empty transcript => fingerprint has 0 useful lines
(define-test (tui-transcript-fingerprint-normalizer-suite empty-transcript)
  (let ((fp (orrery/adapter:build-tui-transcript-fingerprint
             "T1" "" "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
    (is string= "T1" (orrery/adapter:ttf-scenario-id fp))
    (is = 0 (orrery/adapter:ttf-fingerprint fp))))

;; Non-empty transcript => stable fingerprint
(define-test (tui-transcript-fingerprint-normalizer-suite stable-fingerprint)
  (let* ((text (format nil "line1~%line2~%line3~%"))
         (fp1 (orrery/adapter:build-tui-transcript-fingerprint
               "T2" text "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
         (fp2 (orrery/adapter:build-tui-transcript-fingerprint
               "T2" text "cd e2e-tui && ./run-tui-e2e-t1-t6.sh")))
    (is = (orrery/adapter:ttf-fingerprint fp1)
        (orrery/adapter:ttf-fingerprint fp2))
    (true (> (orrery/adapter:ttf-line-count fp1) 0))))

;; Different transcripts => different fingerprints
(define-test (tui-transcript-fingerprint-normalizer-suite different-fingerprints)
  (let* ((fp1 (orrery/adapter:build-tui-transcript-fingerprint
               "T3" (format nil "line-a~%line-b~%") "cmd"))
         (fp2 (orrery/adapter:build-tui-transcript-fingerprint
               "T3" (format nil "line-x~%line-y~%") "cmd")))
    (true (/= (orrery/adapter:ttf-fingerprint fp1)
              (orrery/adapter:ttf-fingerprint fp2)))))

;; JSON fields
(define-test (tui-transcript-fingerprint-normalizer-suite json-fields)
  (let* ((fp (orrery/adapter:build-tui-transcript-fingerprint
              "T4" "content" orrery/adapter:*mcp-tui-deterministic-command*))
         (json (orrery/adapter:tui-transcript-fingerprint->json fp)))
    (true (search "\"scenario\":" json))
    (true (search "\"fingerprint\":" json))
    (true (search "\"line_count\":" json))
    (true (search "\"command_hash\":" json))))

;; Batch: 6 fingerprints for T1-T6
(define-test (tui-transcript-fingerprint-normalizer-suite batch-six-scenarios)
  (let* ((d (format nil "/tmp/orrery-tfb-~D/" (get-universal-time)))
         (batch (progn
                  (ensure-directories-exist (merge-pathnames "dummy" d))
                  (orrery/adapter:compile-tui-fingerprint-batch
                   d orrery/adapter:*mcp-tui-deterministic-command*)))
         (json (orrery/adapter:tui-fingerprint-batch->json batch)))
    (unwind-protect
         (progn
           (is = 6 (length (orrery/adapter:tfb-fingerprints batch)))
           (true (search "\"fingerprints\":" json))
           (true (search "\"command_hash\":" json)))
      (when (probe-file d)
        (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
          (ignore-errors (delete-file f)))))))
