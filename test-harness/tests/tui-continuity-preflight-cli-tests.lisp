;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-continuity-preflight-cli-tests.lisp — Tests for T1-T6 continuity preflight CLI
;;; Bead: agent-orrery-6oh

(in-package #:orrery/harness-tests)

(define-test tui-continuity-preflight-cli-suite)

(defun %mk-tui-pf-dir (prefix)
  (let ((d (format nil "/tmp/orrery-tuipf-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %cleanup-tui-pf (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

;; Empty dir => all missing => pass=false
(define-test (tui-continuity-preflight-cli-suite empty-dir-all-missing)
  (let* ((d (%mk-tui-pf-dir "empty"))
         (v (orrery/adapter:run-tui-continuity-preflight
             d orrery/adapter:*mcp-tui-deterministic-command*)))
    (unwind-protect
         (progn
           (false (orrery/adapter:tcv-pass-p v))
           (is = 6 (length (orrery/adapter:tcv-missing-scenarios v)))
           (true (orrery/adapter:tcv-command-ok-p v)))
      (%cleanup-tui-pf d))))

;; Wrong command => command-ok=false => pass=false
(define-test (tui-continuity-preflight-cli-suite wrong-command-fails)
  (let* ((d (%mk-tui-pf-dir "wc"))
         (v (orrery/adapter:run-tui-continuity-preflight d "wrong-cmd")))
    (unwind-protect
         (progn
           (false (orrery/adapter:tcv-pass-p v))
           (false (orrery/adapter:tcv-command-ok-p v)))
      (%cleanup-tui-pf d))))

;; With all T1-T6 asciicast files present + canonical command => pass=true
(define-test (tui-continuity-preflight-cli-suite all-present-pass)
  (let* ((d (%mk-tui-pf-dir "full")))
    (unwind-protect
         (progn
           (dolist (sid orrery/adapter:*mcp-tui-required-scenarios*)
             (let ((p (merge-pathnames (format nil "~A.cast" sid) (pathname d))))
               (with-open-file (s p :direction :output :if-exists :supersede)
                 (write-string "cast-content" s))))
           (let ((v (orrery/adapter:run-tui-continuity-preflight
                     d orrery/adapter:*mcp-tui-deterministic-command*)))
             (true (orrery/adapter:tcv-pass-p v))
             (is = 0 (length (orrery/adapter:tcv-missing-scenarios v)))
             (is = 6 (orrery/adapter:tcv-complete-count v))))
      (%cleanup-tui-pf d))))

;; JSON fields
(define-test (tui-continuity-preflight-cli-suite json-fields)
  (let* ((d (%mk-tui-pf-dir "json"))
         (v (orrery/adapter:run-tui-continuity-preflight
             d orrery/adapter:*mcp-tui-deterministic-command*))
         (json (orrery/adapter:tui-continuity-verdict->json v)))
    (unwind-protect
         (progn
           (true (search "\"pass\":" json))
           (true (search "\"command_ok\":" json))
           (true (search "\"command_hash\":" json))
           (true (search "\"missing_scenarios\":" json))
           (true (search "\"complete_count\":" json)))
      (%cleanup-tui-pf d))))

;; Command hash matches canonical
(define-test (tui-continuity-preflight-cli-suite canonical-command-hash)
  (let* ((d (%mk-tui-pf-dir "ch"))
         (v (orrery/adapter:run-tui-continuity-preflight
             d orrery/adapter:*mcp-tui-deterministic-command*)))
    (unwind-protect
         (is = (orrery/adapter:command-fingerprint orrery/adapter:*mcp-tui-deterministic-command*)
             (orrery/adapter:tcv-command-hash v))
      (%cleanup-tui-pf d))))
