;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; replay-protocol-bridge-tests.lisp — deterministic trace→protocol parity fixture tests

(in-package #:orrery/harness-tests)

(define-test replay-protocol-bridge-tests)

(defun %trace-event (seq timestamp kind hash)
  (orrery/adapter:make-trace-event
   :seq-id seq
   :timestamp timestamp
   :source-tag :adapter
   :event-kind kind
   :payload-hash hash))

(defun %trace-stream (&rest events)
  (orrery/adapter:make-trace-stream :events events :count (length events)))

(define-test (replay-protocol-bridge-tests event-kind-mapping)
  (is eq :session (orrery/adapter:event-kind->ui-kind :session))
  (is eq :analytics (orrery/adapter:event-kind->ui-kind :usage))
  (is eq :audit (orrery/adapter:event-kind->ui-kind :lifecycle)))

(define-test (replay-protocol-bridge-tests trace-stream->ui-messages)
  (let* ((stream (%trace-stream
                  (%trace-event 1 100 :session 11)
                  (%trace-event 2 101 :health 22)))
         (messages (orrery/adapter:trace-stream->ui-messages stream :web)))
    (is = 2 (length messages))
    (is eq :session (orrery/adapter:uim-kind (first messages)))
    (is eq :health (orrery/adapter:uim-kind (second messages)))
    (is = 1 (orrery/adapter:uim-sequence (first messages)))))

(define-test (replay-protocol-bridge-tests parity-fixture-pass)
  (let* ((stream (%trace-stream
                  (%trace-event 1 100 :session 11)
                  (%trace-event 2 200 :health 12)
                  (%trace-event 3 300 :usage 13)))
         (web (orrery/adapter:trace-stream->ui-messages stream :web))
         (tui (orrery/adapter:trace-stream->ui-messages stream :tui))
         (mc (orrery/adapter:trace-stream->ui-messages stream :mcclim))
         (fixture (orrery/adapter:build-protocol-parity-fixture
                   web tui mc :fixture-id "fx-1" :timestamp 4242)))
    (true (orrery/adapter:ppf-parity-pass-p fixture))
    (is = 3 (orrery/adapter:ppf-row-count fixture))
    (true (search "\"parity_pass\":true"
                  (orrery/adapter:protocol-parity-fixture->json fixture)))))

(define-test (replay-protocol-bridge-tests parity-fixture-mismatch)
  (let* ((stream-a (%trace-stream
                    (%trace-event 1 100 :session 11)
                    (%trace-event 2 200 :health 12)))
         (stream-b (%trace-stream
                    (%trace-event 1 100 :session 11)
                    (%trace-event 2 200 :alert 12)))
         (web (orrery/adapter:trace-stream->ui-messages stream-a :web))
         (tui (orrery/adapter:trace-stream->ui-messages stream-b :tui))
         (mc (orrery/adapter:trace-stream->ui-messages stream-a :mcclim))
         (fixture (orrery/adapter:build-protocol-parity-fixture web tui mc)))
    (false (orrery/adapter:ppf-parity-pass-p fixture))
    (is = 1
        (count-if-not #'orrery/adapter:ppr-parity-p
                      (orrery/adapter:ppf-rows fixture)))))
