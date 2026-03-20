;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-replay-lock-writer-suite)

(defun %mk-temp-lock-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-replay-lock-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %touch-lock-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(define-test (mcp-tui-replay-lock-writer-suite write-and-verify-pass)
  (let* ((dir (%mk-temp-lock-dir "ok"))
         (verdict (merge-pathnames "replay-verdict.json" dir))
         (lock (merge-pathnames "replay-verdict.lock" dir)))
    (%touch-lock-file verdict "{\"pass\":true}")
    (true (orrery/adapter:write-replay-lock-file (namestring verdict) (namestring lock)))
    (let ((check (orrery/adapter:verify-replay-lock-file (namestring verdict) (namestring lock))))
      (true (orrery/adapter:mtrlc-pass-p check)))))

(define-test (mcp-tui-replay-lock-writer-suite verify-fails-hash-drift)
  (let* ((dir (%mk-temp-lock-dir "drift"))
         (verdict (merge-pathnames "replay-verdict.json" dir))
         (lock (merge-pathnames "replay-verdict.lock" dir)))
    (%touch-lock-file verdict "{\"pass\":true}")
    (true (orrery/adapter:write-replay-lock-file (namestring verdict) (namestring lock)))
    (%touch-lock-file verdict "{\"pass\":false}")
    (let ((check (orrery/adapter:verify-replay-lock-file (namestring verdict) (namestring lock))))
      (false (orrery/adapter:mtrlc-pass-p check))
      (is string= "hash-drift" (orrery/adapter:mtrlc-reason check)))))
