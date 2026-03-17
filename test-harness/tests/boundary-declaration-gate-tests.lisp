;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; boundary-declaration-gate-tests.lisp — Tests for adapter/public declaration gate
;;; Bead: agent-orrery-axv

(in-package #:orrery/harness-tests)

(define-test boundary-declaration-gate-tests)

(defun %fresh-temp-package-name (suffix)
  (format nil "ORRERY/HARNESS-TESTS/AXV/~A/~D" suffix (get-universal-time)))

(defun %cleanup-package (name)
  (let ((pkg (find-package name)))
    (when pkg
      (delete-package pkg))))

(define-test (boundary-declaration-gate-tests baseline-detects-known-violations)
  ;; Currently the adapter packages have some undeclared exports.
  ;; Verify the mechanism detects them correctly.
  (let ((violations (boundary-export-declaration-violations)))
    (is eq t (< 0 (length violations)))
    ;; Verify structure of a violation
    (let ((v (first violations)))
      (is eq t (boundary-declaration-violation-p v))
      (is eq :missing-declaration (bdv-reason v)))))

(define-test (boundary-declaration-gate-tests flags-undeclared-export)
  (let* ((package-name (%fresh-temp-package-name "UNDECLARED"))
         (pkg (make-package package-name :use '(:cl)))
         (raw (intern "RAW-ONLY" pkg)))
    (unwind-protect
         (progn
           (export raw pkg)
           (let ((violations (boundary-export-declaration-violations (list package-name))))
             (is = 1 (length violations))
             (let ((v (first violations)))
               (is string= package-name (bdv-package-name v))
               (is string= "RAW-ONLY" (bdv-symbol-name v))
               (is eq :missing-declaration (bdv-reason v)))))
      (%cleanup-package package-name))))

(define-test (boundary-declaration-gate-tests accepts-declared-ftype-and-defstruct)
  (let* ((package-name (%fresh-temp-package-name "DECLARED"))
         (pkg (make-package package-name :use '(:cl))))
    (unwind-protect
         (let* ((type-name (intern "DECLARED-TOKEN" pkg))
                (struct-name (intern "DECLARED-STRUCT" pkg))
                (fn-name (intern "DECLARED-FN" pkg)))
           (eval `(deftype ,type-name () '(member :ok :degraded :blocked)))
           (eval `(defstruct (,struct-name (:conc-name ds-))
                    (status :ok :type ,type-name)))
           (eval `(declaim (ftype (function (,type-name) (values ,type-name &optional))
                                  ,fn-name)))
           (eval `(defun ,fn-name (status)
                    (declare (type ,type-name status))
                    status))
           (export (list type-name
                         struct-name
                         (find-symbol "DECLARED-STRUCT-P" pkg)
                         (find-symbol "MAKE-DECLARED-STRUCT" pkg)
                         (find-symbol "DS-STATUS" pkg)
                         fn-name)
                   pkg)
           (is eq nil (boundary-export-declaration-violations (list package-name))))
      (%cleanup-package package-name))))
