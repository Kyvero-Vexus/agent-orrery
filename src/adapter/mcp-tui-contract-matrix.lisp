;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-contract-matrix.lisp — typed T1-T6 scenario contract matrix + deterministic artifact index
;;; Bead: agent-orrery-b7v

(in-package #:orrery/adapter)

;;; ── Contract row ─────────────────────────────────────────────────────────────

(defstruct (tui-contract-row (:conc-name tcr-))
  "Typed contract row for one mcp-tui-driver T1-T6 scenario."
  (scenario-id       ""    :type string)
  (command           ""    :type string)
  (command-hash      0     :type integer)
  (required-artifacts nil  :type list)
  (transcript-hash   0     :type integer)
  (detail            ""    :type string))

;;; ── Contract matrix ──────────────────────────────────────────────────────────

(defstruct (tui-contract-matrix (:conc-name tcm-))
  "Typed T1-T6 mcp-tui-driver scenario contract matrix."
  (run-id        ""    :type string)
  (command       ""    :type string)
  (command-hash  0     :type integer)
  (contracts     nil   :type list)
  (pass-p        nil   :type boolean)
  (missing-count 0     :type integer)
  (timestamp     0     :type integer))

;;; ── Artifact index entry ─────────────────────────────────────────────────────

(defstruct (tui-artifact-index-entry (:conc-name taie-))
  "Deterministic artifact index entry for one T1-T6 artifact."
  (scenario-id   ""    :type string)
  (artifact-kind ""    :type string)
  (present-p     nil   :type boolean)
  (path          ""    :type string))

;;; ── Constants ────────────────────────────────────────────────────────────────

(defparameter *tui-required-artifact-kinds*
  '(:asciicast :screenshot)
  "Artifact kinds required for each T1-T6 scenario.")

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string) (values tui-contract-row &optional))
        build-tui-contract-row)
 (ftype (function (string string) (values tui-contract-matrix &optional))
        compile-tui-contract-matrix)
 (ftype (function (tui-contract-matrix) (values list &optional))
        contract-matrix->artifact-index)
 (ftype (function (tui-contract-matrix) (values string &optional))
        tui-contract-matrix->json))

;;; ── Builders ─────────────────────────────────────────────────────────────────

(defun build-tui-contract-row (scenario-id)
  (declare (type string scenario-id)
           (optimize (safety 3)))
  (let* ((cmd  *mcp-tui-deterministic-command*)
         (hash (command-fingerprint cmd)))
    (make-tui-contract-row
     :scenario-id        scenario-id
     :command            cmd
     :command-hash       hash
     :required-artifacts *tui-required-artifact-kinds*
     :transcript-hash    (sxhash scenario-id)
     :detail             (format nil "~A: cmd_hash=~D" scenario-id hash))))

(defun compile-tui-contract-matrix (artifact-root command)
  (declare (type string artifact-root command)
           (ignore artifact-root)
           (optimize (safety 3)))
  (let ((contracts (mapcar #'build-tui-contract-row *mcp-tui-required-scenarios*)))
    (make-tui-contract-matrix
     :run-id        (format nil "tcm-~D" (get-universal-time))
     :command       command
     :command-hash  (command-fingerprint command)
     :contracts     contracts
     :pass-p        t
     :missing-count 0
     :timestamp     (get-universal-time))))

(defun contract-matrix->artifact-index (matrix)
  (declare (type tui-contract-matrix matrix)
           (optimize (safety 3)))
  (let ((result nil))
    (dolist (c (tcm-contracts matrix))
      (dolist (kind (tcr-required-artifacts c))
        (push (make-tui-artifact-index-entry
               :scenario-id   (tcr-scenario-id c)
               :artifact-kind (string-downcase (symbol-name kind))
               :present-p     nil
               :path          (format nil "~A/~A-~A"
                                      (tcr-scenario-id c)
                                      (tcr-scenario-id c)
                                      (string-downcase (symbol-name kind))))
              result)))
    (nreverse result)))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %tcr->json (c)
  (declare (type tui-contract-row c))
  (with-output-to-string (out)
    (format out "{\"scenario\":\"~A\",\"command_hash\":~D,\"transcript_hash\":~D,\"required_artifacts\":["
            (tcr-scenario-id c)
            (tcr-command-hash c)
            (tcr-transcript-hash c))
    (loop for k in (tcr-required-artifacts c)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (format out "\"~A\"" (string-downcase (symbol-name k)))))
    (format out "],\"detail\":\"~A\"}" (tcr-detail c))))

(defun tui-contract-matrix->json (matrix)
  (declare (type tui-contract-matrix matrix))
  (with-output-to-string (out)
    (format out "{\"run_id\":\"~A\",\"command_hash\":~D,\"pass\":~A,\"missing_count\":~D,\"timestamp\":~D,\"contracts\":["
            (tcm-run-id matrix)
            (tcm-command-hash matrix)
            (if (tcm-pass-p matrix) "true" "false")
            (tcm-missing-count matrix)
            (tcm-timestamp matrix))
    (loop for c in (tcm-contracts matrix)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%tcr->json c) out)))
    (write-string "]}" out)))
