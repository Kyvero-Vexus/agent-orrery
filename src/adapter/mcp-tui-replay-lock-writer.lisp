;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-replay-lock-writer.lisp — deterministic replay verdict lock writer + verifier
;;; Bead: agent-orrery-ztu4

(in-package #:orrery/adapter)

(defstruct (mcp-tui-replay-lock-check (:conc-name mtrlc-))
  (pass-p nil :type boolean)
  (reason "" :type string)
  (expected-command "" :type string)
  (actual-command "" :type string)
  (expected-hash "" :type string)
  (actual-hash "" :type string))

(declaim
 (ftype (function (string) (values string &optional)) simple-file-hash)
 (ftype (function (string string) (values boolean &optional)) write-replay-lock-file)
 (ftype (function (string string) (values mcp-tui-replay-lock-check &optional)) verify-replay-lock-file)
 (ftype (function (mcp-tui-replay-lock-check) (values string &optional)) replay-lock-check->json))

(defun simple-file-hash (path)
  (declare (type string path))
  (if (probe-file path)
      (with-open-file (s path :direction :input)
        (let ((buf (make-string (file-length s))))
          (read-sequence buf s)
          (write-to-string (sxhash buf))))
      ""))

(defun write-replay-lock-file (verdict-json-path lock-path)
  (declare (type string verdict-json-path lock-path)
           (optimize (safety 3)))
  (let* ((actual-cmd *mcp-tui-deterministic-command*)
         (h (simple-file-hash verdict-json-path)))
    (with-open-file (s lock-path :direction :output :if-exists :supersede)
      (format s "(:deterministic-command ~S :verdict-hash ~S)" actual-cmd h))
    t))

(defun verify-replay-lock-file (verdict-json-path lock-path)
  (declare (type string verdict-json-path lock-path)
           (optimize (safety 3)))
  (let* ((actual-cmd *mcp-tui-deterministic-command*)
         (actual-hash (simple-file-hash verdict-json-path)))
    (if (not (probe-file lock-path))
        (make-mcp-tui-replay-lock-check
         :pass-p nil :reason "lock-missing"
         :expected-command "" :actual-command actual-cmd
         :expected-hash "" :actual-hash actual-hash)
        (with-open-file (s lock-path :direction :input)
          (let* ((plist (read s nil nil))
                 (expected-cmd (or (getf plist :deterministic-command) ""))
                 (expected-hash (or (getf plist :verdict-hash) ""))
                 (cmd-ok (string= expected-cmd actual-cmd))
                 (hash-ok (string= expected-hash actual-hash))
                 (pass (and cmd-ok hash-ok)))
            (make-mcp-tui-replay-lock-check
             :pass-p pass
             :reason (if pass "ok" (if (not cmd-ok) "command-drift" "hash-drift"))
             :expected-command expected-cmd
             :actual-command actual-cmd
             :expected-hash expected-hash
             :actual-hash actual-hash))))))

(defun replay-lock-check->json (check)
  (declare (type mcp-tui-replay-lock-check check))
  (format nil
          "{\"pass\":~A,\"reason\":\"~A\",\"expected_command\":\"~A\",\"actual_command\":\"~A\",\"expected_hash\":\"~A\",\"actual_hash\":\"~A\"}"
          (if (mtrlc-pass-p check) "true" "false")
          (mtrlc-reason check)
          (mtrlc-expected-command check)
          (mtrlc-actual-command check)
          (mtrlc-expected-hash check)
          (mtrlc-actual-hash check)))
