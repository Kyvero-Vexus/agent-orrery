;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; conformance-matrix.lisp — Typed adapter conformance matrix
;;;
;;; Records runtime capabilities, endpoint coverage, and degradation policy.
;;; Integrates with adapter startup to fail-fast on non-conformant runtimes.

(in-package #:orrery/adapter)

;;; ─── Coverage Level ───

(deftype coverage-level ()
  '(member :full :partial :stub :missing))

(deftype degradation-mode ()
  '(member :fail-fast :graceful :best-effort))

;;; ─── Endpoint Coverage Entry ───

(defstruct (coverage-entry
             (:constructor make-coverage-entry
                 (&key endpoint-name coverage tested-at test-verdict notes))
             (:conc-name ce-))
  "Records coverage status for one endpoint."
  (endpoint-name "" :type string)
  (coverage :missing :type coverage-level)
  (tested-at 0 :type integer)
  (test-verdict :skip :type contract-verdict)
  (notes "" :type string))

;;; ─── Conformance Matrix ───

(defstruct (conformance-matrix
             (:constructor make-conformance-matrix
                 (&key adapter-name adapter-version entries
                       degradation-mode minimum-coverage
                       built-at))
             (:conc-name cm-))
  "Complete conformance matrix for an adapter."
  (adapter-name "" :type string)
  (adapter-version "" :type string)
  (entries '() :type list)
  (degradation-mode :fail-fast :type degradation-mode)
  (minimum-coverage :partial :type coverage-level)
  (built-at 0 :type integer))

;;; ─── Conformance Check Result ───

(defstruct (conformance-check-result
             (:constructor make-conformance-check-result
                 (&key conformant-p violations degradation-action summary))
             (:conc-name ccr-))
  "Result of checking runtime conformance against matrix."
  (conformant-p t :type boolean)
  (violations '() :type list)
  (degradation-action :fail-fast :type degradation-mode)
  (summary "" :type string))

;;; ─── Matrix Builder ───

(declaim (ftype (function (harness-result &key (:degradation-mode degradation-mode)
                                          (:minimum-coverage coverage-level))
                          (values conformance-matrix &optional))
                build-conformance-matrix)
         (ftype (function (conformance-matrix) (values conformance-check-result &optional))
                check-conformance)
         (ftype (function (conformance-matrix) (values string &optional))
                conformance-matrix-to-json))

(defun %verdict-to-coverage (verdict)
  "Convert contract verdict to coverage level."
  (declare (type contract-verdict verdict))
  (case verdict
    (:pass :full)
    (:fail :stub)
    (:skip :missing)
    (:error :missing)
    (otherwise :missing)))

(defun build-conformance-matrix (harness-result
                                 &key (degradation-mode :fail-fast)
                                      (minimum-coverage :partial))
  "Build conformance matrix from harness result."
  (declare (type harness-result harness-result))
  (let ((entries '())
        (target (chr-target harness-result)))
    (dolist (check (chr-checks harness-result))
      (push (make-coverage-entry
             :endpoint-name (cc-endpoint-name check)
             :coverage (%verdict-to-coverage (cc-verdict check))
             :tested-at (get-universal-time)
             :test-verdict (cc-verdict check)
             :notes (cc-message check))
            entries))
    (make-conformance-matrix
     :adapter-name (if target (rt-base-url target) "unknown")
     :adapter-version (if target (rt-description target) "")
     :entries (nreverse entries)
     :degradation-mode degradation-mode
     :minimum-coverage minimum-coverage
     :built-at (get-universal-time))))

;;; ─── Conformance Checker ───

(defun %coverage-rank (level)
  (declare (type coverage-level level))
  (case level
    (:full 3)
    (:partial 2)
    (:stub 1)
    (:missing 0)))

(defun check-conformance (matrix)
  "Check whether a conformance matrix meets minimum requirements.
   Returns conformance-check-result with violations list."
  (declare (type conformance-matrix matrix))
  (let ((violations '())
        (min-rank (%coverage-rank (cm-minimum-coverage matrix))))
    (dolist (entry (cm-entries matrix))
      (when (< (%coverage-rank (ce-coverage entry)) min-rank)
        (push (format nil "~A: coverage ~A below minimum ~A"
                      (ce-endpoint-name entry)
                      (ce-coverage entry)
                      (cm-minimum-coverage matrix))
              violations)))
    (let ((conformant (null violations)))
      (make-conformance-check-result
       :conformant-p conformant
       :violations (nreverse violations)
       :degradation-action (if conformant :best-effort (cm-degradation-mode matrix))
       :summary (if conformant
                    (format nil "~A: conformant (~D endpoints at or above ~A)"
                            (cm-adapter-name matrix)
                            (length (cm-entries matrix))
                            (cm-minimum-coverage matrix))
                    (format nil "~A: non-conformant (~D violations, action: ~A)"
                            (cm-adapter-name matrix)
                            (length violations)
                            (cm-degradation-mode matrix)))))))

;;; ─── JSON Serialization ───

(defun conformance-matrix-to-json (matrix)
  "Serialize conformance matrix to deterministic JSON."
  (declare (type conformance-matrix matrix))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"adapter_name\":" s)
    (emit-json-string (cm-adapter-name matrix) s)
    (write-string ",\"degradation_mode\":" s)
    (emit-json-string (string-downcase (symbol-name (cm-degradation-mode matrix))) s)
    (write-string ",\"minimum_coverage\":" s)
    (emit-json-string (string-downcase (symbol-name (cm-minimum-coverage matrix))) s)
    (write-string ",\"entries\":[" s)
    (let ((first t))
      (dolist (e (cm-entries matrix))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"endpoint\":" s)
        (emit-json-string (ce-endpoint-name e) s)
        (write-string ",\"coverage\":" s)
        (emit-json-string (string-downcase (symbol-name (ce-coverage e))) s)
        (write-string ",\"verdict\":" s)
        (emit-json-string (string-downcase (symbol-name (ce-test-verdict e))) s)
        (write-string "}" s)))
    (write-string "]}" s)))
