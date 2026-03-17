;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; adapter-contract-checker.lisp — Typed adapter contract checker core
;;; Beads: agent-orrery-doy, agent-orrery-5ue

(in-package #:orrery/adapter)

(defstruct (adapter-contract-case (:conc-name acc-))
  (surface :tui :type ui-protocol-surface)
  (kind :status :type ui-protocol-kind)
  (payload nil :type list)
  (source "fixture" :type string))

(defstruct (adapter-contract-row (:conc-name acr-))
  (surface :tui :type ui-protocol-surface)
  (kind :status :type ui-protocol-kind)
  (pass-p nil :type boolean)
  (error-count 0 :type fixnum)
  (errors nil :type list)
  (source "fixture" :type string))

(defstruct (adapter-contract-report (:conc-name acp-))
  (pass-p nil :type boolean)
  (rows nil :type list)
  (passed 0 :type fixnum)
  (failed 0 :type fixnum)
  (timestamp 0 :type integer))

(declaim
 (ftype (function () (values list &optional)) make-default-adapter-contract-cases)
 (ftype (function (list) (values adapter-contract-report &optional)) run-adapter-contract-checker)
 (ftype (function (string) (values adapter-contract-report &optional)) run-adapter-contract-checker-from-fixture)
 (ftype (function (adapter-contract-report) (values string &optional)) adapter-contract-report->json))

(defun make-default-adapter-contract-cases ()
  (list
   (make-adapter-contract-case :surface :tui :kind :status
                               :payload (list (cons :id "tui-status-1") (cons :timestamp 1) (cons :state :ok))
                               :source "default")
   (make-adapter-contract-case :surface :web :kind :health
                               :payload (list (cons :component "gateway") (cons :status :ok) (cons :latency-ms 12))
                               :source "default")
   (make-adapter-contract-case :surface :mcclim :kind :analytics
                               :payload (list (cons :total-sessions 3) (cons :total-cost-cents 77))
                               :source "default")))

(defun run-adapter-contract-checker (cases)
  (declare (type list cases))
  (let ((rows nil) (passed 0) (failed 0))
    (dolist (c cases)
      (let* ((schema (make-default-ui-protocol-schema (acc-surface c) (acc-kind c) "1.0"))
             (errors (validate-payload-against-ui-schema schema (acc-payload c)))
             (ok (null errors)))
        (if ok (incf passed) (incf failed))
        (push (make-adapter-contract-row
               :surface (acc-surface c)
               :kind (acc-kind c)
               :pass-p ok
               :error-count (length errors)
               :errors errors
               :source (acc-source c))
              rows)))
    (make-adapter-contract-report
     :pass-p (zerop failed)
     :rows (nreverse rows)
     :passed passed
     :failed failed
     :timestamp (get-universal-time))))

(defun run-adapter-contract-checker-from-fixture (fixture-path)
  "Fixture file must contain a Lisp list of plists with keys :surface :kind :payload [:source]."
  (declare (type string fixture-path))
  (let* ((forms (with-open-file (s fixture-path :direction :input)
                  (read s nil nil)))
         (cases (mapcar (lambda (x)
                          (make-adapter-contract-case
                           :surface (getf x :surface)
                           :kind (getf x :kind)
                           :payload (getf x :payload)
                           :source (or (getf x :source) "fixture")))
                        forms)))
    (run-adapter-contract-checker cases)))

(defun adapter-contract-report->json (report)
  (declare (type adapter-contract-report report))
  (format nil
          "{\"pass\":~A,\"passed\":~D,\"failed\":~D,\"row_count\":~D,\"timestamp\":~D}"
          (if (acp-pass-p report) "true" "false")
          (acp-passed report)
          (acp-failed report)
          (length (acp-rows report))
          (acp-timestamp report)))
