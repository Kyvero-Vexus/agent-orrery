;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; boundary-declaration-gate.lisp — Static declaration gate for adapter/public exports
;;; Bead: agent-orrery-axv

(in-package #:orrery/adapter)

(deftype boundary-declaration-kind ()
  '(member :declared-function :declared-type :declared-variable :undeclared))

(defstruct (boundary-declaration-violation (:conc-name bdv-))
  (package-name "" :type string)
  (symbol-name "" :type string)
  (reason :undeclared :type keyword))

(defparameter *boundary-declaration-packages*
  '("ORRERY/ADAPTER" "ORRERY/ADAPTER/OPENCLAW"))

(declaim
 (ftype (function (symbol) (values (or null string) &optional)) function-where-from-name)
 (ftype (function (symbol) (values boolean &optional)) symbol-has-declared-ftype-p)
 (ftype (function (symbol) (values boolean &optional)) symbol-has-public-type-definition-p)
 (ftype (function (package) (values list &optional)) package-defstruct-helper-symbols)
 (ftype (function (symbol list) (values boundary-declaration-kind &optional))
        boundary-symbol-declaration-kind)
 (ftype (function (&optional list) (values list &optional))
        boundary-export-declaration-violations)
 (ftype (function (&optional list) (values boolean &optional))
        boundary-exports-declared-p))

(defun function-where-from-name (symbol)
  (let ((where (ignore-errors (sb-int:info :function :where-from symbol))))
    (when where
      (symbol-name where))))

(defun symbol-has-declared-ftype-p (symbol)
  (let ((where (function-where-from-name symbol)))
    (and (fboundp symbol)
         (not (macro-function symbol))
         (not (null (member where '("DECLARED" "DEFINED-METHOD") :test #'string=))))))

(defun symbol-has-public-type-definition-p (symbol)
  (let ((kind (nth-value 0 (ignore-errors (sb-int:info :type :kind symbol)))))
    (or (not (null (find-class symbol nil)))
        (and kind
             (not (null (member (symbol-name kind) '("DEFINED" "INSTANCE") :test #'string=)))))))

(defun package-defstruct-helper-symbols (package)
  (let ((helpers '()))
    (do-external-symbols (sym package)
      (let ((dd (ignore-errors (sb-kernel::find-defstruct-description sym))))
        (when dd
          (let ((predicate (ignore-errors (sb-kernel:dd-predicate-name dd))))
            (when (symbolp predicate)
              (pushnew predicate helpers :test #'eq)))
          (let ((copier (ignore-errors (sb-kernel::dd-copier-name dd))))
            (when (symbolp copier)
              (pushnew copier helpers :test #'eq)))
          (dolist (ctor (sb-kernel:dd-constructors dd))
            (let ((ctor-name (car ctor)))
              (when (symbolp ctor-name)
                (pushnew ctor-name helpers :test #'eq))))
          (dolist (slot (sb-kernel:dd-slots dd))
            (let ((accessor (ignore-errors (sb-kernel:dsd-accessor-name slot))))
              (when (symbolp accessor)
                (pushnew accessor helpers :test #'eq)))))))
    helpers))

(defun boundary-symbol-declaration-kind (symbol defstruct-helpers)
  (cond
    ((symbol-has-declared-ftype-p symbol) :declared-function)
    ((member symbol defstruct-helpers :test #'eq) :declared-function)
    ((symbol-has-public-type-definition-p symbol) :declared-type)
    ((boundp symbol) :declared-variable)
    (t :undeclared)))

(defun boundary-export-declaration-violations (&optional (package-names *boundary-declaration-packages*))
  (let ((violations '()))
    (dolist (package-name package-names)
      (let ((pkg (find-package package-name)))
        (if (null pkg)
            (push (make-boundary-declaration-violation
                   :package-name package-name
                   :symbol-name "<package>"
                   :reason :package-not-found)
                  violations)
            (let ((defstruct-helpers (package-defstruct-helper-symbols pkg)))
              (do-external-symbols (sym pkg)
                (when (eq (boundary-symbol-declaration-kind sym defstruct-helpers)
                          :undeclared)
                  (push (make-boundary-declaration-violation
                         :package-name package-name
                         :symbol-name (symbol-name sym)
                         :reason :missing-declaration)
                        violations)))))))
    (nreverse violations)))

(defun boundary-exports-declared-p (&optional (package-names *boundary-declaration-packages*))
  (null (boundary-export-declaration-violations package-names)))
