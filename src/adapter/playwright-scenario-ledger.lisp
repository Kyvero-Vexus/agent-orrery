;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-scenario-ledger.lisp — typed S1-S6 scenario ledger + rerun attestation continuity
;;; Bead: agent-orrery-osb

(in-package #:orrery/adapter)

(defstruct (web-scenario-attestation (:conc-name wsa-))
  (scenario-id "" :type string)
  (command-fingerprint 0 :type integer)
  (screenshot-path "" :type string)
  (trace-path "" :type string)
  (screenshot-hash "" :type string)
  (trace-hash "" :type string)
  (attested-p nil :type boolean))

(defstruct (playwright-scenario-ledger (:conc-name psl-))
  (run-id "" :type string)
  (command "" :type string)
  (attestations nil :type list)
  (timestamp 0 :type integer))

(defstruct (web-continuity-verdict (:conc-name wcv-))
  (pass-p nil :type boolean)
  (missing-scenarios nil :type list)
  (mismatched-scenarios nil :type list)
  (detail "" :type string))

(declaim
 (ftype (function (runner-evidence-manifest string evidence-artifact-kind) (values string &optional))
        find-web-scenario-artifact-path)
 (ftype (function (runner-evidence-manifest string) (values web-scenario-attestation &optional))
        build-web-scenario-attestation)
 (ftype (function ((or null playwright-scenario-ledger) list) (values list boolean &optional))
        compare-web-attestations)
 (ftype (function (string string) (values playwright-scenario-ledger &optional))
        write-playwright-scenario-ledger)
 (ftype (function (playwright-scenario-ledger) (values string &optional))
        playwright-scenario-ledger->json))

(defun %hash-text-file (path)
  (let ((txt (ignore-errors
               (with-open-file (s path :direction :input)
                 (let ((buf (make-string (file-length s))))
                   (read-sequence buf s)
                   buf)))))
    (if txt (write-to-string (sxhash txt)) "")))

(defun find-web-scenario-artifact-path (manifest scenario-id kind)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id)
           (type evidence-artifact-kind kind))
  (let ((art (find-if (lambda (a)
                        (and (string= scenario-id (ea-scenario-id a))
                             (eq kind (ea-artifact-kind a))
                             (ea-present-p a)))
                      (rem-artifacts manifest))))
    (if art (ea-path art) "")))

(defun build-web-scenario-attestation (manifest scenario-id)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id))
  (let* ((screen (find-web-scenario-artifact-path manifest scenario-id :screenshot))
         (trace (find-web-scenario-artifact-path manifest scenario-id :trace))
         (ok (and (plusp (length screen))
                  (plusp (length trace))))
         (cmd (rem-command manifest)))
    (make-web-scenario-attestation
     :scenario-id scenario-id
     :command-fingerprint (sxhash cmd)
     :screenshot-path screen
     :trace-path trace
     :screenshot-hash (%hash-text-file screen)
     :trace-hash (%hash-text-file trace)
     :attested-p ok)))

(defun compare-web-attestations (previous current)
  (declare (type (or null playwright-scenario-ledger) previous)
           (type list current))
  (let ((missing nil)
        (mismatch nil))
    (if (null previous)
        (values nil t)
        (progn
          (dolist (sid *default-web-scenarios*)
            (let ((p (find sid (psl-attestations previous) :key #'wsa-scenario-id :test #'string=))
                  (c (find sid current :key #'wsa-scenario-id :test #'string=)))
              (cond
                ((or (null p) (null c) (not (wsa-attested-p p)) (not (wsa-attested-p c)))
                 (push sid missing))
                ((or (/= (wsa-command-fingerprint p) (wsa-command-fingerprint c))
                     (not (string= (wsa-screenshot-hash p) (wsa-screenshot-hash c)))
                     (not (string= (wsa-trace-hash p) (wsa-trace-hash c))))
                 (push sid mismatch)))))
          (values (append (nreverse missing) (nreverse mismatch))
                  (and (null missing) (null mismatch)))))))

(defun %web-ledger->sexp (ledger)
  (list :run-id (psl-run-id ledger)
        :command (psl-command ledger)
        :timestamp (psl-timestamp ledger)
        :attestations
        (mapcar (lambda (a)
                  (list :scenario-id (wsa-scenario-id a)
                        :command-fingerprint (wsa-command-fingerprint a)
                        :screenshot-path (wsa-screenshot-path a)
                        :trace-path (wsa-trace-path a)
                        :screenshot-hash (wsa-screenshot-hash a)
                        :trace-hash (wsa-trace-hash a)
                        :attested-p (wsa-attested-p a)))
                (psl-attestations ledger))))

(defun %sexp->web-ledger (sexp)
  (let ((atts (mapcar (lambda (x)
                        (make-web-scenario-attestation
                         :scenario-id (getf x :scenario-id)
                         :command-fingerprint (getf x :command-fingerprint)
                         :screenshot-path (getf x :screenshot-path)
                         :trace-path (getf x :trace-path)
                         :screenshot-hash (getf x :screenshot-hash)
                         :trace-hash (getf x :trace-hash)
                         :attested-p (getf x :attested-p)))
                      (getf sexp :attestations))))
    (make-playwright-scenario-ledger
     :run-id (getf sexp :run-id)
     :command (getf sexp :command)
     :timestamp (getf sexp :timestamp)
     :attestations atts)))

(defun %read-web-ledger-sexp (path)
  (let ((p (if (pathnamep path) path (pathname path))))
    (when (probe-file p)
      (with-open-file (s p :direction :input)
        (let ((f (read s nil nil)))
          (when f (%sexp->web-ledger f)))))))

(defun %write-web-ledger-sexp (path ledger)
  (with-open-file (s (if (pathnamep path) path (pathname path))
                     :direction :output :if-exists :supersede)
    (prin1 (%web-ledger->sexp ledger) s))
  t)

(defun write-playwright-scenario-ledger (artifact-root command)
  (declare (type string artifact-root command))
  (let* ((manifest (compile-playwright-evidence-manifest artifact-root command))
         (att (mapcar (lambda (sid) (build-web-scenario-attestation manifest sid))
                      *default-web-scenarios*))
         (ledger (make-playwright-scenario-ledger
                  :run-id (format nil "playwright-run-~D" (get-universal-time))
                  :command command
                  :attestations att
                  :timestamp (get-universal-time)))
         (root-abs (uiop:ensure-absolute-pathname (pathname artifact-root)
                                                  (uiop:getcwd))))
    (let ((out (merge-pathnames "playwright-scenario-ledger.json" root-abs))
          (sexp (merge-pathnames "playwright-scenario-ledger.sexp" root-abs))
          (prev (merge-pathnames "playwright-scenario-ledger.prev.sexp" root-abs)))
      (when (probe-file sexp)
        (ignore-errors (delete-file prev))
        (ignore-errors (rename-file sexp prev)))
      (%write-web-ledger-sexp sexp ledger)
      (with-open-file (s out :direction :output :if-exists :supersede)
        (write-string (playwright-scenario-ledger->json ledger) s))
      ledger)))

(defun playwright-scenario-ledger->json (ledger)
  (declare (type playwright-scenario-ledger ledger))
  (with-output-to-string (out)
    (format out
            "{\"run_id\":\"~A\",\"command\":\"~A\",\"command_hash\":~D,\"attestation_count\":~D,\"missing_attestations\":~D,\"timestamp\":~D,\"scenarios\":["
            (psl-run-id ledger)
            (psl-command ledger)
            (command-fingerprint (psl-command ledger))
            (length (psl-attestations ledger))
            (count-if-not #'wsa-attested-p (psl-attestations ledger))
            (psl-timestamp ledger))
    (loop for att in (psl-attestations ledger)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out
                       "{\"scenario\":\"~A\",\"attested\":~A,\"command_hash\":~D,\"screenshot_path\":\"~A\",\"trace_path\":\"~A\"}"
                       (wsa-scenario-id att)
                       (if (wsa-attested-p att) "true" "false")
                       (wsa-command-fingerprint att)
                       (wsa-screenshot-path att)
                       (wsa-trace-path att))))
    (write-string "]}" out)))
