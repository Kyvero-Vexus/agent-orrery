;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-scenario-ledger.lisp — Typed T1-T6 deterministic rerun ledger (h9i)

(in-package #:orrery/adapter)

(defstruct (scenario-rerun-attestation
             (:constructor make-scenario-rerun-attestation
                 (&key scenario-id command-fingerprint artifact-fingerprint
                       transcript-fingerprint continuity-pass-p detail))
             (:conc-name sra-))
  (scenario-id "" :type string)
  (command-fingerprint 0 :type integer)
  (artifact-fingerprint "" :type string)
  (transcript-fingerprint "" :type string)
  (continuity-pass-p nil :type boolean)
  (detail "" :type string))

(defstruct (tui-scenario-ledger
             (:constructor make-tui-scenario-ledger
                 (&key command command-fingerprint artifact-root
                       scenario-attestations continuity-pass-p timestamp))
             (:conc-name tsl-))
  (command "" :type string)
  (command-fingerprint 0 :type integer)
  (artifact-root "" :type string)
  (scenario-attestations '() :type list)
  (continuity-pass-p nil :type boolean)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string) (values string &optional)) file-sha256)
 (ftype (function (runner-evidence-manifest string evidence-artifact-kind)
                  (values (or null string) &optional))
        find-scenario-artifact-path)
 (ftype (function (runner-evidence-manifest string) (values scenario-rerun-attestation &optional))
        build-scenario-attestation)
 (ftype (function ((or null tui-scenario-ledger) list)
                  (values list boolean &optional))
        compare-attestations)
 (ftype (function ((or string pathname)) (values (or null tui-scenario-ledger) &optional))
        read-tui-scenario-ledger-sexp)
 (ftype (function (tui-scenario-ledger) (values string &optional))
        tui-scenario-ledger->json)
 (ftype (function (string string (or string pathname) &key (:previous-ledger-path (or null string pathname)))
                  (values tui-scenario-ledger &optional))
        write-tui-scenario-ledger))

(defun file-sha256 (path)
  (declare (type string path))
  (let* ((result (uiop:run-program (list "sha256sum" path)
                                   :output :string
                                   :ignore-error-status t))
         (line (if (stringp result)
                   (car (uiop:split-string result :separator '(#\Newline)))
                   ""))
         (parts (uiop:split-string line :separator '(#\Space #\Tab))))
    (if (and (consp parts) (> (length (car parts)) 0))
        (car parts)
        "")))

(defun find-scenario-artifact-path (manifest scenario-id kind)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id)
           (type evidence-artifact-kind kind))
  (let ((match (find-if (lambda (artifact)
                          (and (eq kind (ea-artifact-kind artifact))
                               (string= scenario-id (normalize-scenario-id (ea-scenario-id artifact)))
                               (ea-present-p artifact)))
                        (rem-artifacts manifest))))
    (when match
      (ea-path match))))

(defun build-scenario-attestation (manifest scenario-id)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id))
  (let* ((artifact-path (find-scenario-artifact-path manifest scenario-id :screenshot))
         (transcript-path (find-scenario-artifact-path manifest scenario-id :transcript))
         (artifact-fp (if artifact-path (file-sha256 artifact-path) ""))
         (transcript-fp (if transcript-path (file-sha256 transcript-path) "")))
    (make-scenario-rerun-attestation
     :scenario-id scenario-id
     :command-fingerprint (command-fingerprint (rem-command manifest))
     :artifact-fingerprint artifact-fp
     :transcript-fingerprint transcript-fp
     :continuity-pass-p nil
     :detail "pending-rerun-compare")))

(defun %attestation-equal-p (a b)
  (declare (type scenario-rerun-attestation a b))
  (and (= (sra-command-fingerprint a) (sra-command-fingerprint b))
       (string= (sra-artifact-fingerprint a) (sra-artifact-fingerprint b))
       (string= (sra-transcript-fingerprint a) (sra-transcript-fingerprint b))))

(defun %find-prior-attestation (prior scenario-id)
  (declare (type list prior)
           (type string scenario-id))
  (find scenario-id prior :key #'sra-scenario-id :test #'string=))

(defun compare-attestations (prior-ledger current-attestations)
  (declare (type (or null tui-scenario-ledger) prior-ledger)
           (type list current-attestations))
  (let ((updated '())
        (all-pass t))
    (dolist (curr current-attestations)
      (let* ((prior (and prior-ledger
                         (%find-prior-attestation
                          (tsl-scenario-attestations prior-ledger)
                          (sra-scenario-id curr))))
             (pass (if prior (%attestation-equal-p curr prior) t))
             (detail (cond
                       ((null prior) "baseline-established")
                       (pass "continuity-ok")
                       (t "continuity-mismatch"))))
        (unless pass (setf all-pass nil))
        (push (make-scenario-rerun-attestation
               :scenario-id (sra-scenario-id curr)
               :command-fingerprint (sra-command-fingerprint curr)
               :artifact-fingerprint (sra-artifact-fingerprint curr)
               :transcript-fingerprint (sra-transcript-fingerprint curr)
               :continuity-pass-p pass
               :detail detail)
              updated)))
    (values (nreverse updated) all-pass)))

(defun %ledger->sexp (ledger)
  (declare (type tui-scenario-ledger ledger))
  (list :command (tsl-command ledger)
        :command-fingerprint (tsl-command-fingerprint ledger)
        :artifact-root (tsl-artifact-root ledger)
        :continuity-pass-p (tsl-continuity-pass-p ledger)
        :timestamp (tsl-timestamp ledger)
        :scenario-attestations
        (mapcar (lambda (item)
                  (list :scenario-id (sra-scenario-id item)
                        :command-fingerprint (sra-command-fingerprint item)
                        :artifact-fingerprint (sra-artifact-fingerprint item)
                        :transcript-fingerprint (sra-transcript-fingerprint item)
                        :continuity-pass-p (sra-continuity-pass-p item)
                        :detail (sra-detail item)))
                (tsl-scenario-attestations ledger))))

(defun %sexp->ledger (form)
  (declare (type list form))
  (let ((items (getf form :scenario-attestations)))
    (make-tui-scenario-ledger
     :command (or (getf form :command) "")
     :command-fingerprint (or (getf form :command-fingerprint) 0)
     :artifact-root (or (getf form :artifact-root) "")
     :continuity-pass-p (and (getf form :continuity-pass-p) t)
     :timestamp (or (getf form :timestamp) 0)
     :scenario-attestations
     (mapcar (lambda (row)
               (make-scenario-rerun-attestation
                :scenario-id (or (getf row :scenario-id) "")
                :command-fingerprint (or (getf row :command-fingerprint) 0)
                :artifact-fingerprint (or (getf row :artifact-fingerprint) "")
                :transcript-fingerprint (or (getf row :transcript-fingerprint) "")
                :continuity-pass-p (and (getf row :continuity-pass-p) t)
                :detail (or (getf row :detail) "")))
             items))))

(defun read-tui-scenario-ledger-sexp (path)
  (declare (type (or string pathname) path))
  (let ((p (if (pathnamep path) path (pathname path))))
    (when (probe-file p)
      (with-open-file (s p :direction :input)
        (let ((form (read s nil nil)))
          (when form
            (%sexp->ledger form)))))))

(defun %write-ledger-sexp (path ledger)
  (declare (type (or string pathname) path)
           (type tui-scenario-ledger ledger))
  (with-open-file (s (if (pathnamep path) path (pathname path)) :direction :output :if-exists :supersede)
    (write (%ledger->sexp ledger) :stream s :pretty nil))
  ledger)

(defun tui-scenario-ledger->json (ledger)
  (declare (type tui-scenario-ledger ledger))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"command\":" s)
    (emit-json-string (tsl-command ledger) s)
    (write-string ",\"command_fingerprint\":" s)
    (format s "~D" (tsl-command-fingerprint ledger))
    (write-string ",\"artifact_root\":" s)
    (emit-json-string (tsl-artifact-root ledger) s)
    (write-string ",\"continuity_pass\":" s)
    (write-string (if (tsl-continuity-pass-p ledger) "true" "false") s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (tsl-timestamp ledger))
    (write-string ",\"scenarios\":[" s)
    (let ((first t))
      (dolist (row (tsl-scenario-attestations ledger))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{" s)
        (write-string "\"scenario_id\":" s)
        (emit-json-string (sra-scenario-id row) s)
        (write-string ",\"command_fingerprint\":" s)
        (format s "~D" (sra-command-fingerprint row))
        (write-string ",\"artifact_fingerprint\":" s)
        (emit-json-string (sra-artifact-fingerprint row) s)
        (write-string ",\"transcript_fingerprint\":" s)
        (emit-json-string (sra-transcript-fingerprint row) s)
        (write-string ",\"continuity_pass\":" s)
        (write-string (if (sra-continuity-pass-p row) "true" "false") s)
        (write-string ",\"detail\":" s)
        (emit-json-string (sra-detail row) s)
        (write-string "}" s)))
    (write-string "]}" s)))

(defun write-tui-scenario-ledger (artifact-root command out-path &key previous-ledger-path)
  (declare (type string artifact-root command)
           (type (or string pathname) out-path)
           (type (or null string pathname) previous-ledger-path))
  (let* ((manifest (compile-mcp-tui-evidence-manifest artifact-root command))
         (report (verify-runner-evidence
                  manifest
                  *default-tui-scenarios*
                  *tui-required-artifacts*
                  '(:machine-report :asciicast)
                  *expected-tui-command*))
         (prior-path (or previous-ledger-path
                         (format nil "~A.sexp"
                                 (if (pathnamep out-path) (namestring out-path) out-path))))
         (prior (read-tui-scenario-ledger-sexp prior-path))
         (attestations (mapcar (lambda (sid) (build-scenario-attestation manifest sid))
                               *default-tui-scenarios*))
         (compared nil)
         (continuity-pass nil))
    (multiple-value-setq (compared continuity-pass)
      (compare-attestations prior attestations))
    (let ((ledger (make-tui-scenario-ledger
                   :command command
                   :command-fingerprint (command-fingerprint command)
                   :artifact-root artifact-root
                   :scenario-attestations compared
                   :continuity-pass-p (and (ecr-pass-p report) continuity-pass)
                   :timestamp (get-universal-time))))
      (%write-ledger-sexp prior-path ledger)
      (with-open-file (s out-path :direction :output :if-exists :supersede)
        (write-string (tui-scenario-ledger->json ledger) s))
      ledger)))
