;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; notification-routing-tests.lisp — Tests for typed notification dispatcher
;;; Bead: agent-orrery-78i

(in-package #:orrery/harness-tests)

(define-test notification-routing-suite

  (define-test critical-routes-to-all-channels
    (let* ((cfg (orrery/coalton/core:cl-default-dispatcher-config))
           (ev (orrery/coalton/core:cl-make-notification-event
                "a1" :critical "CPU high" "system" 100 :pending))
           (decision (orrery/coalton/core:cl-dispatch-notification ev cfg nil))
           (channels (orrery/coalton/core:cl-route-channel-keywords decision)))
      (false (orrery/coalton/core:cl-route-suppressed-p decision))
      (true (orrery/coalton/core:cl-route-requires-ack-p decision))
      (true (member :tui-overlay channels :test #'eq))
      (true (member :web-toast channels :test #'eq))
      (true (member :mcclim-pane channels :test #'eq))))

  (define-test warning-routes-to-tui-and-web
    (let* ((cfg (orrery/coalton/core:cl-default-dispatcher-config))
           (ev (orrery/coalton/core:cl-make-notification-event
                "a2" :warning "Budget warning" "budget" 101 :none))
           (decision (orrery/coalton/core:cl-dispatch-notification ev cfg nil))
           (channels (orrery/coalton/core:cl-route-channel-keywords decision)))
      (true (member :tui-overlay channels :test #'eq))
      (true (member :web-toast channels :test #'eq))
      (false (member :mcclim-pane channels :test #'eq))
      (false (orrery/coalton/core:cl-route-requires-ack-p decision))))

  (define-test dedupe-suppresses-duplicate
    (let* ((cfg (orrery/coalton/core:cl-default-dispatcher-config))
           (ev (orrery/coalton/core:cl-make-notification-event
                "a3" :warning "Disk warning" "system" 102 :none))
           (seen (list "system|Disk warning|warning"))
           (decision (orrery/coalton/core:cl-dispatch-notification ev cfg seen)))
      (true (orrery/coalton/core:cl-route-suppressed-p decision))
      (is string= "suppressed-duplicate" (orrery/coalton/core:cl-route-reason decision))
      (is = 0 (length (orrery/coalton/core:cl-route-channel-keywords decision)))))

  (define-test dedupe-disabled-allows-duplicate
    (let* ((cfg (orrery/coalton/core:cl-make-dispatcher-config t t t nil 80))
           (ev (orrery/coalton/core:cl-make-notification-event
                "a4" :warning "Disk warning" "system" 103 :none))
           (seen (list "system|Disk warning|warning"))
           (decision (orrery/coalton/core:cl-dispatch-notification ev cfg seen)))
      (false (orrery/coalton/core:cl-route-suppressed-p decision))
      (is string= "dispatched" (orrery/coalton/core:cl-route-reason decision))))

  (define-test disabled-channel-is-respected
    (let* ((cfg (orrery/coalton/core:cl-make-dispatcher-config t nil t t 80))
           (ev (orrery/coalton/core:cl-make-notification-event
                "a5" :critical "Node down" "gateway" 104 :pending))
           (decision (orrery/coalton/core:cl-dispatch-notification ev cfg nil))
           (channels (orrery/coalton/core:cl-route-channel-keywords decision)))
      (true (member :tui-overlay channels :test #'eq))
      (false (member :web-toast channels :test #'eq))
      (true (member :mcclim-pane channels :test #'eq))))

  (define-test dedup-key-shape
    (let* ((cfg (orrery/coalton/core:cl-default-dispatcher-config))
           (ev (orrery/coalton/core:cl-make-notification-event
                "a6" :info "Hello" "test" 105 :none))
           (decision (orrery/coalton/core:cl-dispatch-notification ev cfg nil))
           (key (orrery/coalton/core:cl-route-dedup-key decision)))
      (true (search "test|Hello|info" key))))
)
