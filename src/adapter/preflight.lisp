;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; preflight.lisp — Typed live-gate preflight command + CI wiring
;;;
;;; Classifies target runtime compatibility before E2E execution.
;;; Emits deterministic machine-readable diagnostics.
;;; No UI coupling — pure library consumed by CI scripts.

(in-package #:orrery/adapter)

;;; ─── Preflight Check Types ───

(deftype preflight-status ()
  '(member :pass :fail :skip :warn))

(defstruct (preflight-check
             (:constructor make-preflight-check
                 (&key name status message details))
             (:conc-name pc-))
  "One preflight check result."
  (name "" :type string)
  (status :skip :type preflight-status)
  (message "" :type string)
  (details '() :type list))  ; alist of extra data

(defstruct (preflight-report
             (:constructor make-preflight-report
                 (&key checks overall-status timestamp adapter-name))
             (:conc-name pr-))
  "Complete preflight report for CI consumption."
  (checks '() :type list)
  (overall-status :skip :type preflight-status)
  (timestamp 0 :type integer)
  (adapter-name "" :type string))

;;; ─── Preflight Runner ───

(declaim (ftype (function (string list &key (:check-fn t))
                          (values preflight-report &optional))
                run-preflight)
         (ftype (function (list) (values preflight-status &optional))
                compute-overall-status)
         (ftype (function (preflight-report) (values string &optional))
                preflight-report-to-sexp))

(defun compute-overall-status (checks)
  "Compute overall status from list of checks. Any :fail → :fail, any :warn → :warn."
  (declare (type list checks))
  (cond
    ((some (lambda (c) (eq :fail (pc-status c))) checks) :fail)
    ((some (lambda (c) (eq :warn (pc-status c))) checks) :warn)
    ((every (lambda (c) (eq :pass (pc-status c))) checks) :pass)
    (t :skip)))

(defun run-preflight (base-url paths &key (check-fn nil))
  "Run preflight checks against an adapter endpoint.
   CHECK-FN: (lambda (base-url path) → (values usable-p alt-url-or-nil))
   If CHECK-FN is nil, all paths are marked :skip.
   Returns a preflight-report with one check per path."
  (declare (type string base-url) (type list paths))
  (let ((checks '()))
    (dolist (path paths)
      (multiple-value-bind (usable alt-url)
          (if check-fn
              (funcall check-fn base-url path)
              (values nil nil))
        (push (make-preflight-check
               :name (format nil "endpoint:~A" path)
               :status (cond (usable :pass)
                             (check-fn :fail)
                             (t :skip))
               :message (cond (usable
                               (format nil "~A is accessible~A"
                                       path (if alt-url " (via fallback)" "")))
                              (check-fn
                               (format nil "~A is not accessible" path))
                              (t
                               (format nil "~A skipped (no check function)" path)))
               :details (list (cons "path" path)
                              (cons "usable" (if usable "true" "false"))
                              (cons "alternative" (or alt-url ""))))
              checks)))
    (let ((ordered (nreverse checks)))
      (make-preflight-report
       :checks ordered
       :overall-status (compute-overall-status ordered)
       :timestamp (get-universal-time)
       :adapter-name base-url))))

(defun preflight-report-to-sexp (report)
  "Serialize preflight report to deterministic s-expression string."
  (declare (type preflight-report report))
  (with-output-to-string (s)
    (format s "((:overall-status . ~S)~%" (pr-overall-status report))
    (format s " (:adapter-name . ~S)~%" (pr-adapter-name report))
    (format s " (:timestamp . ~D)~%" (pr-timestamp report))
    (format s " (:checks . (")
    (dolist (c (pr-checks report))
      (format s "~%   ((:name . ~S) (:status . ~S) (:message . ~S))"
              (pc-name c) (pc-status c) (pc-message c)))
    (format s ")))~%")))
