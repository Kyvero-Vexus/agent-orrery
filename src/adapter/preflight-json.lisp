;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; preflight-json.lisp — Deterministic JSON emitter for preflight reports
;;;
;;; Pure formatting functions with stable key ordering.
;;; No external JSON library dependency — hand-rolled for determinism.

(in-package #:orrery/adapter)

;;; ─── JSON Emitter ───

(declaim (ftype (function (string stream) (values &optional)) emit-json-string)
         (ftype (function (preflight-check stream) (values &optional)) emit-check-json)
         (ftype (function (preflight-report) (values string &optional)) preflight-report-to-json)
         (ftype (function (gate-result) (values string &optional)) gate-result-to-json))

(defun emit-json-string (s stream)
  "Emit a JSON-escaped string (with quotes) to stream."
  (declare (type string s) (type stream stream))
  (write-char #\" stream)
  (loop for c across s do
    (case c
      (#\" (write-string "\\\"" stream))
      (#\\ (write-string "\\\\" stream))
      (#\Newline (write-string "\\n" stream))
      (#\Tab (write-string "\\t" stream))
      (otherwise (write-char c stream))))
  (write-char #\" stream)
  (values))

(defun emit-check-json (check stream)
  "Emit one preflight check as JSON object with stable key order."
  (declare (type preflight-check check) (type stream stream))
  (write-string "{" stream)
  (write-string "\"name\":" stream)
  (emit-json-string (pc-name check) stream)
  (write-string ",\"status\":" stream)
  (emit-json-string (string-downcase (symbol-name (pc-status check))) stream)
  (write-string ",\"message\":" stream)
  (emit-json-string (pc-message check) stream)
  (write-string "}" stream)
  (values))

(defun preflight-report-to-json (report)
  "Serialize preflight report to deterministic JSON with stable key ordering."
  (declare (type preflight-report report))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"adapter_name\":" s)
    (emit-json-string (pr-adapter-name report) s)
    (write-string ",\"overall_status\":" s)
    (emit-json-string (string-downcase (symbol-name (pr-overall-status report))) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (pr-timestamp report))
    (write-string ",\"checks\":[" s)
    (let ((first t))
      (dolist (c (pr-checks report))
        (unless first (write-char #\, s))
        (setf first nil)
        (emit-check-json c s)))
    (write-string "]}" s)))

(defun gate-result-to-json (result)
  "Serialize gate result to deterministic JSON."
  (declare (type gate-result result))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"gate_passed\":" s)
    (write-string (if (gr-gate-passed-p result) "true" "false") s)
    (write-string ",\"exit_code\":" s)
    (format s "~D" (gr-exit-code result))
    (write-string ",\"applied_policies\":[" s)
    (let ((first t))
      (dolist (p (gr-applied-policies result))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"check_name\":" s)
        (emit-json-string (fp-check-name p) s)
        (write-string ",\"action\":" s)
        (emit-json-string (string-downcase (symbol-name (fp-action p))) s)
        (write-string ",\"rationale\":" s)
        (emit-json-string (fp-rationale p) s)
        (write-string "}" s)))
    (write-string "]" s)
    (when (gr-report result)
      (write-string ",\"report\":" s)
      (write-string (preflight-report-to-json (gr-report result)) s))
    (write-string "}" s)))
