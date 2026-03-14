;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capability-mapper-tests.lisp — Tests for command-capability mapper + safe executors

(in-package #:orrery/harness-tests)

(define-test capability-mapper-tests)

(define-test (capability-mapper-tests build-gate-from-capabilities)
  (let* ((caps (list (orrery/domain:make-adapter-capability
                      :name "list-sessions" :description "List sessions" :supported-p t)
                     (orrery/domain:make-adapter-capability
                      :name "trigger-cron" :description "Trigger cron" :supported-p t)
                     (orrery/domain:make-adapter-capability
                      :name "system-health" :description "Health" :supported-p nil)))
         (gate (orrery/adapter/openclaw:build-capability-gate caps)))
    (true (orrery/adapter/openclaw:operation-allowed-p gate :list-sessions))
    (true (orrery/adapter/openclaw:operation-allowed-p gate :trigger-cron))
    ;; system-health has supported-p=nil → denied
    (false (orrery/adapter/openclaw:operation-allowed-p gate :system-health))
    ;; Never added → denied
    (false (orrery/adapter/openclaw:operation-allowed-p gate :pause-cron))))

(define-test (capability-mapper-tests safe-execute-allowed)
  (let* ((caps (list (orrery/domain:make-adapter-capability
                      :name "list-sessions" :description "yes" :supported-p t)))
         (gate (orrery/adapter/openclaw:build-capability-gate caps))
         (req (orrery/adapter/openclaw:make-command-request :kind :list-sessions))
         (res (orrery/adapter/openclaw:safe-execute gate req)))
    (true (orrery/adapter/openclaw:cmd-res-ok-p res))
    (is eq :list-sessions (orrery/adapter/openclaw:cmd-res-kind res))))

(define-test (capability-mapper-tests safe-execute-denied)
  (let* ((gate (orrery/adapter/openclaw:build-capability-gate '()))
         (req (orrery/adapter/openclaw:make-command-request :kind :trigger-cron))
         (res (orrery/adapter/openclaw:safe-execute gate req)))
    (false (orrery/adapter/openclaw:cmd-res-ok-p res))
    (true (stringp (orrery/adapter/openclaw:cmd-res-error-detail res)))
    (true (search "denied" (orrery/adapter/openclaw:cmd-res-error-detail res)))))

(define-test (capability-mapper-tests empty-capabilities-denies-everything)
  (let ((gate (orrery/adapter/openclaw:build-capability-gate '())))
    (false (orrery/adapter/openclaw:operation-allowed-p gate :list-sessions))
    (false (orrery/adapter/openclaw:operation-allowed-p gate :trigger-cron))
    (false (orrery/adapter/openclaw:operation-allowed-p gate :acknowledge-alert))))
