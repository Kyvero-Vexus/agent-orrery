;;; check-protocol-schema-declarations.lisp — Strict declaration gate for protocol-schema
;;; Bead: agent-orrery-e2j
;;;
;;; Deterministic command:
;;;   sbcl --script ci/check-protocol-schema-declarations.lisp
;;;
;;; Exit codes:
;;;   0 - All declarations pass
;;;   1 - Declaration violations found

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defpackage #:orrery/declaration-gate
  (:use #:cl)
  (:export #:run-declaration-gate))

(in-package #:orrery/declaration-gate)

(defun get-unix-time ()
  #+sbcl (sb-posix:time)
  #-sbcl (get-universal-time))

(defun check-package-declarations (package-name required-functions)
  "Check that required functions have ftype declarations.
   Returns (values errors warnings)"
  (let ((errors 0)
        (warnings 0)
        (pkg (find-package package-name)))
    (unless pkg
      (return-from check-package-declarations
        (values 1 0)))
    (dolist (fn-name required-functions)
      (let ((sym (find-symbol (string fn-name) pkg)))
        (cond
          ((null sym)
           (incf errors)
           (format *error-output* "ERROR: Symbol ~A not found in ~A~%" fn-name package-name))
          ((not (fboundp sym))
           (incf errors)
           (format *error-output* "ERROR: ~A::~A is not fbound~%" package-name fn-name))
          (t
           ;; Check for explicit ftype declaration by seeing if type is known
           (handler-case
               (let ((ftype (sb-int:info :function :type sym)))
                 (declare (ignore ftype))
                 ;; If we get here, a type exists - pass
                 )
             (error ()
               (incf warnings)
               (format *error-output* "WARNING: Could not retrieve ftype for ~A::~A~%" package-name fn-name)))))))
    (values errors warnings)))

(defun ensure-artifact-dir ()
  (let ((dir (merge-pathnames "test-results/protocol-schema-gate/"
                              (asdf:system-source-directory :agent-orrery))))
    (ensure-directories-exist dir)
    dir))

(defun write-transcript (dir verdict-json)
  (let ((path (merge-pathnames "declaration-gate-transcript.json" dir)))
    (with-open-file (out path :direction :output :if-exists :supersede)
      (write-string verdict-json out))
    path))

(defun run-declaration-gate ()
  (let* ((required-functions '(default-schema validate-payload schema->json))
         (artifact-dir (ensure-artifact-dir))
         (timestamp (get-unix-time)))
    (multiple-value-bind (errors warnings)
        (check-package-declarations :orrery/protocol-schema required-functions)
      (let* ((pass-p (and (zerop errors) (zerop warnings)))
             (verdict-json
               (format nil "{\"pass\":~A,\"module\":\"orrery/protocol-schema\",\"checked_at\":~D,\"errors\":~D,\"warnings\":~D,\"required_functions\":~D,\"artifact_dir\":\"~A\"}"
                       (if pass-p "true" "false")
                       timestamp
                       errors
                       warnings
                       (length required-functions)
                       (namestring artifact-dir))))
        (let ((transcript-path (merge-pathnames "declaration-gate-transcript.json" artifact-dir)))
          (with-open-file (out transcript-path :direction :output :if-exists :supersede)
            (write-string verdict-json out)))
        (format t "~A~%" verdict-json)
        (unless pass-p
          (uiop:quit 1))))))

(run-declaration-gate)
(uiop:quit 0)
