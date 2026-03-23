;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-transcript-fingerprint-normalizer.lisp — typed T1-T6 transcript fingerprint normalizer
;;; Bead: agent-orrery-309

(in-package #:orrery/adapter)

;;; ── Normalized line ──────────────────────────────────────────────────────────

(defstruct (tui-normalized-line (:conc-name tnl-))
  "One canonicalized transcript line."
  (original  "" :type string)
  (canonical "" :type string)
  (index     0  :type (integer 0)))

;;; ── Fingerprint result ───────────────────────────────────────────────────────

(defstruct (tui-transcript-fingerprint (:conc-name ttf-))
  "Deterministic fingerprint for one T1-T6 transcript."
  (scenario-id     ""    :type string)
  (line-count      0     :type (integer 0))
  (fingerprint     0     :type integer)
  (command         ""    :type string)
  (command-hash    0     :type integer)
  (canonical-lines nil   :type list)    ; list of tui-normalized-line
  (detail          ""    :type string))

;;; ── Normalization batch ──────────────────────────────────────────────────────

(defstruct (tui-fingerprint-batch (:conc-name tfb-))
  "Batch of T1-T6 transcript fingerprints."
  (run-id      ""    :type string)
  (command     ""    :type string)
  (command-hash 0    :type integer)
  (fingerprints nil  :type list)    ; list of tui-transcript-fingerprint
  (pass-p      nil   :type boolean)
  (timestamp   0     :type integer))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string) (values string &optional))
        canonicalize-transcript-line)
 (ftype (function (string string string) (values tui-transcript-fingerprint &optional))
        build-tui-transcript-fingerprint)
 (ftype (function (string string) (values tui-fingerprint-batch &optional))
        compile-tui-fingerprint-batch)
 (ftype (function (tui-transcript-fingerprint) (values string &optional))
        tui-transcript-fingerprint->json)
 (ftype (function (tui-fingerprint-batch) (values string &optional))
        tui-fingerprint-batch->json))

;;; ── Canonicalization ─────────────────────────────────────────────────────────

(defun canonicalize-transcript-line (line)
  "Strip trailing whitespace and normalize CRLF to LF for stable fingerprinting."
  (declare (type string line)
           (optimize (safety 3)))
  (string-right-trim '(#\Space #\Tab #\Return #\Newline)
                     (substitute #\Newline #\Return line)))

(defun %normalize-lines (raw-text)
  "Split raw-text on newlines, canonicalize each line, return list of tui-normalized-line."
  (declare (type string raw-text))
  (let ((lines (uiop:split-string raw-text :separator '(#\Newline)))
        (result nil)
        (idx 0))
    (dolist (line lines)
      (let ((canon (canonicalize-transcript-line line)))
        (push (make-tui-normalized-line :original line :canonical canon :index idx) result)
        (incf idx)))
    (nreverse result)))

(defun %stable-fingerprint (canonical-lines)
  "Compute stable integer fingerprint over canonical line contents."
  (declare (type list canonical-lines))
  (reduce (lambda (acc line)
            (logxor (ash acc 3)
                    (sxhash (tnl-canonical line))))
          canonical-lines
          :initial-value 0))

;;; ── Builders ─────────────────────────────────────────────────────────────────

(defun build-tui-transcript-fingerprint (scenario-id transcript-text command)
  "Build a deterministic fingerprint for one T1-T6 transcript."
  (declare (type string scenario-id transcript-text command)
           (optimize (safety 3)))
  (let* ((lines (%normalize-lines transcript-text))
         (fp    (%stable-fingerprint lines))
         (ch    (command-fingerprint command)))
    (make-tui-transcript-fingerprint
     :scenario-id     scenario-id
     :line-count      (length lines)
     :fingerprint     fp
     :command         command
     :command-hash    ch
     :canonical-lines lines
     :detail          (format nil "~A: lines=~D fingerprint=~D cmd_hash=~D"
                              scenario-id (length lines) fp ch))))

(defun compile-tui-fingerprint-batch (artifact-root command)
  "Build fingerprint batch for all T1-T6 scenarios from ARTIFACT-ROOT."
  (declare (type string artifact-root command)
           (optimize (safety 3)))
  (let* ((fingerprints
           (mapcar (lambda (sid)
                     (let* ((path (format nil "~A~A-transcript.txt" artifact-root sid))
                            (text (if (probe-file path)
                                      (with-open-file (s path :direction :input)
                                        (let ((buf (make-string (file-length s))))
                                          (read-sequence buf s)
                                          buf))
                                      "")))
                       (build-tui-transcript-fingerprint sid text command)))
                   *mcp-tui-required-scenarios*))
         (pass (every (lambda (fp) (> (ttf-line-count fp) 0)) fingerprints)))
    (make-tui-fingerprint-batch
     :run-id        (format nil "tfb-~D" (get-universal-time))
     :command       command
     :command-hash  (command-fingerprint command)
     :fingerprints  fingerprints
     :pass-p        pass
     :timestamp     (get-universal-time))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun tui-transcript-fingerprint->json (fp)
  (declare (type tui-transcript-fingerprint fp))
  (format nil "{\"scenario\":\"~A\",\"line_count\":~D,\"fingerprint\":~D,\"command_hash\":~D,\"detail\":\"~A\"}"
          (ttf-scenario-id fp)
          (ttf-line-count fp)
          (ttf-fingerprint fp)
          (ttf-command-hash fp)
          (ttf-detail fp)))

(defun tui-fingerprint-batch->json (batch)
  (declare (type tui-fingerprint-batch batch))
  (with-output-to-string (out)
    (format out "{\"run_id\":\"~A\",\"command_hash\":~D,\"pass\":~A,\"timestamp\":~D,\"fingerprints\":["
            (tfb-run-id batch)
            (tfb-command-hash batch)
            (if (tfb-pass-p batch) "true" "false")
            (tfb-timestamp batch))
    (loop for fp in (tfb-fingerprints batch)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (tui-transcript-fingerprint->json fp) out)))
    (write-string "]}" out)))
