;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; plugin-lifecycle-hooks-tests.lisp — Tests for v2 plugin lifecycle hooks
;;; Bead: agent-orrery-a3p

(in-package #:orrery/harness-tests)

;; Test plugin class with lifecycle hooks
(defclass test-lifecycle-plugin (orrery/plugin:plugin) ()
  (:default-initargs :name "test-lifecycle" :version "2.0.0"))

(defmethod orrery/plugin:plugin-lifecycle-hooks ((p test-lifecycle-plugin))
  (list
   (orrery/plugin:make-lifecycle-hook
    :name "audit-logger"
    :module :audit-trail
    :phase :after
    :handler (lambda (data) (format nil "logged: ~A" data))
    :priority 10)
   (orrery/plugin:make-lifecycle-hook
    :name "cost-alerter"
    :module :cost-optimizer
    :phase :after
    :handler (lambda (data) (format nil "alert: ~A" data))
    :priority 20)))

(define-test plugin-lifecycle-hooks-suite

  (define-test hook-struct-creation
    (let ((hook (orrery/plugin:make-lifecycle-hook
                 :name "test" :module :audit-trail :phase :before
                 :handler (lambda (x) x) :priority 5)))
      (is string= "test" (orrery/plugin:lh-name hook))
      (is eq :audit-trail (orrery/plugin:lh-module hook))
      (is eq :before (orrery/plugin:lh-phase hook))
      (is = 5 (orrery/plugin:lh-priority hook))))

  (define-test dispatch-matching-hooks
    (let* ((plugin (make-instance 'test-lifecycle-plugin))
           (results (orrery/plugin:dispatch-lifecycle-hooks
                     plugin :audit-trail :after "test-data")))
      (is = 1 (length results))
      (is string= "audit-logger" (car (first results)))
      (true (search "logged: test-data" (cdr (first results))))))

  (define-test dispatch-no-match
    (let* ((plugin (make-instance 'test-lifecycle-plugin))
           (results (orrery/plugin:dispatch-lifecycle-hooks
                     plugin :capacity-planner :after "data")))
      (is = 0 (length results))))

  (define-test dispatch-wrong-phase
    (let* ((plugin (make-instance 'test-lifecycle-plugin))
           (results (orrery/plugin:dispatch-lifecycle-hooks
                     plugin :audit-trail :before "data")))
      (is = 0 (length results))))

  (define-test dispatch-error-handling
    (let* ((plugin (make-instance 'orrery/plugin:plugin :name "err" :version "1.0.0")))
      ;; Plugin with no hooks — empty result
      (let ((results (orrery/plugin:dispatch-lifecycle-hooks
                      plugin :audit-trail :after "data")))
        (is = 0 (length results)))))

  (define-test default-generic-methods-return-nil
    (let ((plugin (make-instance 'orrery/plugin:plugin :name "base" :version "1.0.0")))
      (is eq nil (orrery/plugin:plugin-lifecycle-hooks plugin))
      (is eq nil (orrery/plugin:plugin-on-audit-event plugin "event"))
      (is eq nil (orrery/plugin:plugin-on-cost-recommendation plugin "rec"))
      (is eq nil (orrery/plugin:plugin-on-capacity-assessment plugin "plan"))
      (is eq nil (orrery/plugin:plugin-on-session-analytics plugin "summary"))
      (is eq nil (orrery/plugin:plugin-on-scenario-projection plugin "result"))))

  (define-test hook-phase-type
    (true (typep :before 'orrery/plugin::hook-phase))
    (true (typep :after 'orrery/plugin::hook-phase))
    (true (typep :error 'orrery/plugin::hook-phase))
    (false (typep :invalid 'orrery/plugin::hook-phase))))
