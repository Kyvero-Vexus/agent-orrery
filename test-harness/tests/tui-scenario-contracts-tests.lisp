;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-scenario-contracts-tests.lisp — Tests for T1-T6 deterministic contracts
;;; Bead: agent-orrery-igw.1

(in-package #:orrery/harness-tests)

(define-test tui-scenario-contracts-suite

  (define-test contracts-cover-t1-t6
    (let ((contracts (orrery/adapter:tui-scenario-contracts)))
      (true (orrery/adapter:tui-contracts-cover-t1-t6-p contracts))
      (is = 6 (length contracts))))

  (define-test deterministic-command
    (is string= "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
        (orrery/adapter:tui-deterministic-contract-command))
    (dolist (c (orrery/adapter:tui-scenario-contracts))
      (is string= "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
          (orrery/adapter:tsc-deterministic-command c))))

  (define-test required-artifacts-declared
    (let ((missing (orrery/adapter:missing-tui-contract-artifacts
                    (orrery/adapter:tui-scenario-contracts))))
      (is = 0 (length missing))))

  (define-test t1-includes-suite-artifacts
    (let* ((contracts (orrery/adapter:tui-scenario-contracts))
           (t1 (find :T1 contracts :key #'orrery/adapter:tsc-id :test #'eq)))
      (true t1)
      (true (member :report (orrery/adapter:tsc-required-artifacts t1) :test #'eq))
      (true (member :asciicast (orrery/adapter:tsc-required-artifacts t1) :test #'eq))))

  (define-test malformed-contract-set-fails-coverage
    (let ((bad (list (orrery/adapter:make-tui-scenario-contract :id :T1)
                     (orrery/adapter:make-tui-scenario-contract :id :T1))))
      (false (orrery/adapter:tui-contracts-cover-t1-t6-p bad)))))
