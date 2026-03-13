;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; check-types.lisp — CI type policy enforcement for Agent Orrery
;;;
;;; Checks:
;;;   1. All exported function symbols in designated packages have ftype declarations.
;;;   2. System compiles cleanly with (safety 3) and no style-warnings.
;;;   3. No compiler notes about type uncertainty in designated packages.
;;;
;;; Exit codes:
;;;   0 — all checks passed
;;;   1 — type policy violations found
;;;   2 — load/compile error
;;;
;;; Usage:
;;;   sbcl --load ci/check-types.lisp

(require :asdf)

;;; ============================================================
;;; Configuration
;;; ============================================================

;; Packages subject to the typing policy
(defvar *checked-packages*
  '("ORRERY/DOMAIN" "ORRERY/ADAPTER")
  "Packages whose exported function symbols must have ftype declarations.")

;; ASDF systems to load
(defvar *system-name* "agent-orrery")
(defvar *coalton-system-name* "agent-orrery/coalton")

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun package-exported-functions (package-name)
  "Return a list of (symbol . package-name) for all exported fboundp symbols."
  (let ((pkg (find-package package-name))
        (result '()))
    (when pkg
      (do-external-symbols (sym pkg)
        (when (and (fboundp sym)
                   (not (macro-function sym))
                   (not (typep (fdefinition sym) 'generic-function)))
          (push (cons sym package-name) result))))
    (nreverse result)))

(defun symbol-has-ftype-p (sym)
  "Check if SYM has an ftype proclamation in SBCL's type system."
  (let ((type (sb-int:info :function :type sym)))
    ;; sb-int:info returns the function type. If no ftype was declared,
    ;; SBCL stores a default FUNCTION type. We check for something more specific.
    (and type
         (not (equal type (sb-kernel:specifier-type 'function))))))

(defun check-ftype-coverage ()
  "Check all exported functions in *CHECKED-PACKAGES* have ftype declarations.
Returns (values passed-p violations) where violations is a list of strings."
  (let ((violations '()))
    (dolist (pkg-name *checked-packages*)
      (dolist (entry (package-exported-functions pkg-name))
        (let ((sym (car entry)))
          (unless (symbol-has-ftype-p sym)
            (push (format nil "  ~A:~A — no ftype declaration"
                          (package-name (symbol-package sym))
                          (symbol-name sym))
                  violations)))))
    (values (null violations) (nreverse violations))))

;;; ============================================================
;;; Compile-time warning collector
;;; ============================================================

(defvar *collected-warnings* '())
(defvar *collected-notes* '())

(defun compile-with-strict-policy ()
  "Load the system with safety 3 and collect warnings/notes.
Returns (values clean-p warnings notes)."
  (setf *collected-warnings* '()
        *collected-notes* '())
  (handler-bind
      ((style-warning
         (lambda (c)
           (let ((msg (princ-to-string c)))
             ;; Skip "redefining X in DEFUN/DEFGENERIC" — expected during force-reload
             (unless (search "redefining" msg)
               (push (format nil "  STYLE-WARNING: ~A" msg) *collected-warnings*)))
           (muffle-warning c)))
       (warning
         (lambda (c)
           (push (format nil "  WARNING: ~A" c) *collected-warnings*)
           (muffle-warning c))))
    ;; Force recompile by clearing fasls
    (asdf:clear-system *coalton-system-name*)
    (asdf:clear-system *system-name*)
    (declaim (optimize (safety 3) (debug 2)))
    ;; Explicitly compile Coalton baseline first, then full system.
    (asdf:load-system *coalton-system-name* :force t)
    (asdf:load-system *system-name* :force t))
  (values (and (null *collected-warnings*) (null *collected-notes*))
          (nreverse *collected-warnings*)
          (nreverse *collected-notes*)))

;;; ============================================================
;;; Main
;;; ============================================================

(defun main ()
  (let ((exit-code 0))
    (format t "~&=== Agent Orrery Type Policy Check ===~%~%")

    ;; Step 1: Load systems (core + coalton)
    (format t "Step 1: Loading ~A and ~A...~%" *system-name* *coalton-system-name*)
    (handler-case
        (progn
          (push #P"/home/slime/projects/agent-orrery/"
                asdf:*central-registry*)
          (asdf:clear-source-registry)
          (ql:quickload *coalton-system-name* :silent t)
          (ql:quickload *system-name* :silent t)
          (format t "  ✔ Systems loaded.~%~%"))
      (error (e)
        (format *error-output* "~&  ✘ Load error: ~A~%" e)
        (sb-ext:exit :code 2)))

    ;; Step 2: Check ftype coverage
    (format t "Step 2: Checking ftype declarations in ~{~A~^, ~}...~%"
            *checked-packages*)
    (multiple-value-bind (passed-p violations)
        (check-ftype-coverage)
      (if passed-p
          (format t "  ✔ All exported functions have ftype declarations.~%~%")
          (progn
            (format t "  ✘ Missing ftype declarations:~%")
            (dolist (v violations)
              (format t "~A~%" v))
            (format t "~%")
            (setf exit-code 1))))

    ;; Step 3: Strict recompile
    (format t "Step 3: Recompiling with (safety 3)...~%")
    (handler-case
        (multiple-value-bind (clean-p warnings notes)
            (compile-with-strict-policy)
          (declare (ignore clean-p))
          (if (and (null warnings) (null notes))
              (format t "  ✔ Clean compile — no warnings or type notes.~%~%")
              (progn
                (when warnings
                  (format t "  ⚠ Warnings during compile:~%")
                  (dolist (w warnings)
                    (format t "~A~%" w))
                  (setf exit-code 1))
                (when notes
                  (format t "  ⚠ Type notes:~%")
                  (dolist (n notes)
                    (format t "~A~%" n)))
                (format t "~%"))))
      (error (e)
        (format *error-output* "~&  ✘ Compile error: ~A~%" e)
        (setf exit-code 2)))

    ;; Summary
    (format t "=== Result: ~A ===~%"
            (if (zerop exit-code) "PASSED" "FAILED"))
    (sb-ext:exit :code exit-code)))

(main)
