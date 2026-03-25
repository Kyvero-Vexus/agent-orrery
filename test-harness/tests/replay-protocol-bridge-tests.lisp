;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; replay-protocol-bridge-tests.lisp — deterministic replay contract + typed error ADT tests
;;; Extended: Bead agent-orrery-111

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
        (count-if-not #'orrery/adapter:protocol-par-parity-p
                      (orrery/adapter:ppf-rows fixture)))))

;;; ── Extended tests for bead 111: deterministic replay contracts + error ADT ─

;; Deterministic: same trace stream → same ui-messages (sequence stability)
(define-test (replay-protocol-bridge-tests deterministic-replay-stability)
  (let* ((stream (%trace-stream
                  (%trace-event 1 100 :session 42)
                  (%trace-event 2 200 :health 43)
                  (%trace-event 3 300 :usage 44)))
         (run1 (orrery/adapter:trace-stream->ui-messages stream :web))
         (run2 (orrery/adapter:trace-stream->ui-messages stream :web)))
    (is = (length run1) (length run2))
    (loop for m1 in run1 for m2 in run2
          do (progn
               (is eq (orrery/adapter:uim-kind m1) (orrery/adapter:uim-kind m2))
               (is = (orrery/adapter:uim-sequence m1) (orrery/adapter:uim-sequence m2))))))

;; Surface-specific: tui vs web may differ in surface tag but same seq
(define-test (replay-protocol-bridge-tests tui-vs-web-same-sequence)
  (let* ((stream (%trace-stream
                  (%trace-event 1 100 :session 10)))
         (web (orrery/adapter:trace-stream->ui-messages stream :web))
         (tui (orrery/adapter:trace-stream->ui-messages stream :tui)))
    (is = 1 (length web))
    (is = 1 (length tui))
    (is = (orrery/adapter:uim-sequence (first web))
        (orrery/adapter:uim-sequence (first tui)))))

;; Empty stream → empty message list (edge case)
(define-test (replay-protocol-bridge-tests empty-stream-empty-messages)
  (let* ((stream (orrery/adapter:make-trace-stream :events nil :count 0))
         (msgs (orrery/adapter:trace-stream->ui-messages stream :web)))
    (is = 0 (length msgs))))

;; Parity JSON well-formed (no nils in output)
(define-test (replay-protocol-bridge-tests parity-json-well-formed)
  (let* ((stream (%trace-stream
                  (%trace-event 1 100 :session 1)
                  (%trace-event 2 200 :health 2)))
         (web (orrery/adapter:trace-stream->ui-messages stream :web))
         (tui (orrery/adapter:trace-stream->ui-messages stream :tui))
         (mc  (orrery/adapter:trace-stream->ui-messages stream :mcclim))
         (fx  (orrery/adapter:build-protocol-parity-fixture web tui mc))
         (json (orrery/adapter:protocol-parity-fixture->json fx)))
    (false (search "NIL" json))
    (true (search "\"rows\":" json))
    (true (search "\"parity_pass\":" json))))

;; Cross-surface count consistency
(define-test (replay-protocol-bridge-tests cross-surface-count-consistency)
  (let* ((stream (%trace-stream
                  (%trace-event 1 100 :session 10)
                  (%trace-event 2 200 :health 20)
                  (%trace-event 3 300 :alert 30)))
         (web (orrery/adapter:trace-stream->ui-messages stream :web))
         (tui (orrery/adapter:trace-stream->ui-messages stream :tui))
         (mc  (orrery/adapter:trace-stream->ui-messages stream :mcclim))
         (fx  (orrery/adapter:build-protocol-parity-fixture web tui mc)))
    (is = 3 (orrery/adapter:ppf-row-count fx))
    (is = (length web) (length tui))
    (is = (length tui) (length mc))))
