;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; session-lifecycle-tests.lisp — Tests for Coalton session lifecycle state machine
;;; Bead: agent-orrery-q8r
;;;
;;; Uses symbol-presence + direct (coalton ...) evaluation.

(in-package #:orrery/harness-tests)

;;; ─── Symbol presence tests ───

(define-test session-lifecycle-suite

  ;; ADT types exist
  (define-test sl-state-type-exists
    (true (find-symbol "SESSIONSTATE" :orrery/coalton/core)))

  (define-test sl-event-type-exists
    (true (find-symbol "TRANSITIONEVENT" :orrery/coalton/core)))

  (define-test sl-result-type-exists
    (true (find-symbol "TRANSITIONRESULT" :orrery/coalton/core)))

  ;; State constructors
  (define-test sl-state-constructors
    (true (find-symbol "SESSIONCREATING" :orrery/coalton/core))
    (true (find-symbol "SESSIONACTIVE" :orrery/coalton/core))
    (true (find-symbol "SESSIONIDLE" :orrery/coalton/core))
    (true (find-symbol "SESSIONCLOSING" :orrery/coalton/core))
    (true (find-symbol "SESSIONCLOSED" :orrery/coalton/core))
    (true (find-symbol "SESSIONERROR" :orrery/coalton/core)))

  ;; Event constructors
  (define-test sl-event-constructors
    (true (find-symbol "EVINITIALIZED" :orrery/coalton/core))
    (true (find-symbol "EVMESSAGERECEIVED" :orrery/coalton/core))
    (true (find-symbol "EVIDLETIMEOUT" :orrery/coalton/core))
    (true (find-symbol "EVSHUTDOWNREQUESTED" :orrery/coalton/core))
    (true (find-symbol "EVSHUTDOWNCOMPLETE" :orrery/coalton/core))
    (true (find-symbol "EVFATALERROR" :orrery/coalton/core))
    (true (find-symbol "EVRESTART" :orrery/coalton/core)))

  ;; Result constructors
  (define-test sl-result-constructors
    (true (find-symbol "TRANSITIONOK" :orrery/coalton/core))
    (true (find-symbol "TRANSITIONDENIED" :orrery/coalton/core)))

  ;; Core functions
  (define-test sl-core-functions
    (true (find-symbol "TRANSITION" :orrery/coalton/core))
    (true (find-symbol "VALIDATE-TRANSITION-SEQUENCE" :orrery/coalton/core))
    (true (find-symbol "COUNT-VALID-TRANSITIONS" :orrery/coalton/core))
    (true (find-symbol "SESSION-STATE-TERMINAL-P" :orrery/coalton/core))
    (true (find-symbol "SESSION-STATE-ALIVE-P" :orrery/coalton/core))
    (true (find-symbol "SESSION-STATE-LABEL" :orrery/coalton/core))
    (true (find-symbol "TRANSITION-EVENT-LABEL" :orrery/coalton/core)))

  ;; Canonical paths
  (define-test sl-canonical-paths
    (true (find-symbol "HAPPY-PATH-EVENTS" :orrery/coalton/core))
    (true (find-symbol "ERROR-PATH-EVENTS" :orrery/coalton/core)))

  ;; ─── State label tests ───

  (define-test sl-label-creating
    (is string= "creating"
        (coalton:coalton (orrery/coalton/core:session-state-label
                  orrery/coalton/core:SessionCreating))))

  (define-test sl-label-active
    (is string= "active"
        (coalton:coalton (orrery/coalton/core:session-state-label
                  orrery/coalton/core:SessionActive))))

  (define-test sl-label-idle
    (is string= "idle"
        (coalton:coalton (orrery/coalton/core:session-state-label
                  orrery/coalton/core:SessionIdle))))

  (define-test sl-label-closing
    (is string= "closing"
        (coalton:coalton (orrery/coalton/core:session-state-label
                  orrery/coalton/core:SessionClosing))))

  (define-test sl-label-closed
    (is string= "closed"
        (coalton:coalton (orrery/coalton/core:session-state-label
                  orrery/coalton/core:SessionClosed))))

  (define-test sl-label-error
    (is string= "error"
        (coalton:coalton (orrery/coalton/core:session-state-label
                  orrery/coalton/core:SessionError))))

  ;; ─── Event label tests ───

  (define-test sl-event-initialized
    (is string= "initialized"
        (coalton:coalton (orrery/coalton/core:transition-event-label
                  orrery/coalton/core:EvInitialized))))

  (define-test sl-event-fatal-error
    (is string= "fatal-error"
        (coalton:coalton (orrery/coalton/core:transition-event-label
                  orrery/coalton/core:EvFatalError))))

  (define-test sl-event-restart
    (is string= "restart"
        (coalton:coalton (orrery/coalton/core:transition-event-label
                  orrery/coalton/core:EvRestart))))

  ;; ─── Terminal/alive predicates ───

  (define-test sl-creating-not-terminal
    (is eq nil
        (coalton:coalton (orrery/coalton/core:session-state-terminal-p
                  orrery/coalton/core:SessionCreating))))

  (define-test sl-closed-is-terminal
    (is eq t
        (coalton:coalton (orrery/coalton/core:session-state-terminal-p
                  orrery/coalton/core:SessionClosed))))

  (define-test sl-error-is-terminal
    (is eq t
        (coalton:coalton (orrery/coalton/core:session-state-terminal-p
                  orrery/coalton/core:SessionError))))

  (define-test sl-active-not-terminal
    (is eq nil
        (coalton:coalton (orrery/coalton/core:session-state-terminal-p
                  orrery/coalton/core:SessionActive))))

  (define-test sl-creating-is-alive
    (is eq t
        (coalton:coalton (orrery/coalton/core:session-state-alive-p
                  orrery/coalton/core:SessionCreating))))

  (define-test sl-active-is-alive
    (is eq t
        (coalton:coalton (orrery/coalton/core:session-state-alive-p
                  orrery/coalton/core:SessionActive))))

  (define-test sl-idle-is-alive
    (is eq t
        (coalton:coalton (orrery/coalton/core:session-state-alive-p
                  orrery/coalton/core:SessionIdle))))

  (define-test sl-closing-not-alive
    (is eq nil
        (coalton:coalton (orrery/coalton/core:session-state-alive-p
                  orrery/coalton/core:SessionClosing))))

  (define-test sl-closed-not-alive
    (is eq nil
        (coalton:coalton (orrery/coalton/core:session-state-alive-p
                  orrery/coalton/core:SessionClosed))))

  ;; ─── Transition count tests ───

  (define-test sl-happy-path-5-transitions
    (is = 5
        (coalton:coalton (orrery/coalton/core:count-valid-transitions
                  orrery/coalton/core:SessionCreating
                  (orrery/coalton/core:happy-path-events coalton:Unit)))))

  (define-test sl-error-path-3-transitions
    (is = 3
        (coalton:coalton (orrery/coalton/core:count-valid-transitions
                  orrery/coalton/core:SessionCreating
                  (orrery/coalton/core:error-path-events coalton:Unit))))))
