;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; conformance-tests.lisp — Adapter conformance suite tests
;;;

(in-package #:orrery/harness-tests)

(define-test adapter-conformance-tests)

(define-test (adapter-conformance-tests fixture-conformance-suite)
  (multiple-value-bind (ok failures)
      (run-adapter-conformance-suite (make-fixture-adapter) :exercise-commands t)
    (true ok)
    (is = 0 (length failures))))

(define-test (adapter-conformance-tests openclaw-mock-conformance-suite)
  ;; make-mock-adapter comes from openclaw-adapter-tests file in same package.
  (multiple-value-bind (ok failures)
      (run-adapter-conformance-suite (make-mock-adapter) :exercise-commands t)
    (true ok)
    (is = 0 (length failures))))

(define-test (adapter-conformance-tests openclaw-live-optional)
  (let ((base #+sbcl (sb-ext:posix-getenv "ORRERY_OPENCLAW_BASE_URL")
              #-sbcl nil))
    (if (or (null base) (string= base ""))
        (true t)
        (let ((adapter (make-openclaw-adapter
                        :base-url base
                        :api-token #+sbcl (sb-ext:posix-getenv "ORRERY_OPENCLAW_TOKEN")
                                   #-sbcl nil
                        :timeout-s 5)))
          ;; Live mode may not support every command on every runtime.
          ;; Run without command exercise to validate generic read contract.
          (multiple-value-bind (ok failures)
              (run-adapter-conformance-suite adapter :exercise-commands nil)
            (true ok)
            (is = 0 (length failures)))))))
