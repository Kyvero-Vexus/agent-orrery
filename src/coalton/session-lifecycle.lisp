;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; session-lifecycle.lisp — Coalton typed session lifecycle state machine
;;;
;;; Pure ADT for session lifecycle states with verified transitions.
;;; Total: no partial functions, explicit Result types for all operations.
;;; Bead: agent-orrery-q8r

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Session Lifecycle States ───

  (define-type SessionState
    "Session lifecycle states. Total enumeration."
    SessionCreating    ; Session being initialized
    SessionActive      ; Running, processing messages
    SessionIdle        ; No activity, still allocated
    SessionClosing     ; Graceful shutdown in progress
    SessionClosed      ; Terminated normally
    SessionError)      ; Terminated with error

  ;; ─── Transition Events ───

  (define-type TransitionEvent
    "Events that trigger state transitions."
    EvInitialized      ; Creation complete → Active
    EvMessageReceived  ; Activity detected → Active (from Idle)
    EvIdleTimeout      ; No activity for threshold → Idle
    EvShutdownRequested ; Graceful close requested → Closing
    EvShutdownComplete  ; Cleanup finished → Closed
    EvFatalError        ; Unrecoverable error → Error
    EvRestart)          ; Recovery attempt → Creating (from Error)

  ;; ─── Transition Result ───

  (define-type TransitionResult
    "Result of attempting a state transition."
    (TransitionOk SessionState)         ; Valid transition, new state
    (TransitionDenied String))          ; Invalid transition, reason

  ;; ─── State Predicates ───

  (declare session-state-terminal-p (SessionState -> Boolean))
  (define (session-state-terminal-p state)
    "True if the state is a terminal state (no further transitions expected)."
    (match state
      ((SessionClosed) True)
      ((SessionError) True)
      (_ False)))

  (declare session-state-alive-p (SessionState -> Boolean))
  (define (session-state-alive-p state)
    "True if the session is in a live state (creating, active, or idle)."
    (match state
      ((SessionCreating) True)
      ((SessionActive) True)
      ((SessionIdle) True)
      (_ False)))

  ;; ─── State Display ───

  (declare session-state-label (SessionState -> String))
  (define (session-state-label state)
    "Canonical string label for a session state."
    (match state
      ((SessionCreating) "creating")
      ((SessionActive) "active")
      ((SessionIdle) "idle")
      ((SessionClosing) "closing")
      ((SessionClosed) "closed")
      ((SessionError) "error")))

  (declare transition-event-label (TransitionEvent -> String))
  (define (transition-event-label ev)
    "Canonical string label for a transition event."
    (match ev
      ((EvInitialized) "initialized")
      ((EvMessageReceived) "message-received")
      ((EvIdleTimeout) "idle-timeout")
      ((EvShutdownRequested) "shutdown-requested")
      ((EvShutdownComplete) "shutdown-complete")
      ((EvFatalError) "fatal-error")
      ((EvRestart) "restart")))

  ;; ─── Transition Function ───

  (declare transition (SessionState -> TransitionEvent -> TransitionResult))
  (define (transition current-state event)
    "Evaluate a state transition. Total: all state×event pairs handled.
     Returns TransitionOk with new state or TransitionDenied with reason."
    (match current-state
      ;; Creating: can initialize, error, or be shut down
      ((SessionCreating)
       (match event
         ((EvInitialized) (TransitionOk SessionActive))
         ((EvFatalError) (TransitionOk SessionError))
         ((EvShutdownRequested) (TransitionOk SessionClosing))
         (_ (TransitionDenied
             (mconcat (make-list "Cannot "
                                (transition-event-label event)
                                " from creating"))))))
      ;; Active: can idle, close, error, or receive messages (stay active)
      ((SessionActive)
       (match event
         ((EvMessageReceived) (TransitionOk SessionActive))
         ((EvIdleTimeout) (TransitionOk SessionIdle))
         ((EvShutdownRequested) (TransitionOk SessionClosing))
         ((EvFatalError) (TransitionOk SessionError))
         (_ (TransitionDenied
             (mconcat (make-list "Cannot "
                                (transition-event-label event)
                                " from active"))))))
      ;; Idle: can reactivate, close, or error
      ((SessionIdle)
       (match event
         ((EvMessageReceived) (TransitionOk SessionActive))
         ((EvShutdownRequested) (TransitionOk SessionClosing))
         ((EvFatalError) (TransitionOk SessionError))
         ((EvIdleTimeout) (TransitionOk SessionIdle))
         (_ (TransitionDenied
             (mconcat (make-list "Cannot "
                                (transition-event-label event)
                                " from idle"))))))
      ;; Closing: can complete or error
      ((SessionClosing)
       (match event
         ((EvShutdownComplete) (TransitionOk SessionClosed))
         ((EvFatalError) (TransitionOk SessionError))
         (_ (TransitionDenied
             (mconcat (make-list "Cannot "
                                (transition-event-label event)
                                " from closing"))))))
      ;; Closed: terminal, only restart allowed
      ((SessionClosed)
       (match event
         ((EvRestart) (TransitionOk SessionCreating))
         (_ (TransitionDenied
             (mconcat (make-list "Cannot "
                                (transition-event-label event)
                                " from closed"))))))
      ;; Error: terminal, only restart allowed
      ((SessionError)
       (match event
         ((EvRestart) (TransitionOk SessionCreating))
         (_ (TransitionDenied
             (mconcat (make-list "Cannot "
                                (transition-event-label event)
                                " from error"))))))))

  ;; ─── Transition Sequence Validator ───

  (declare validate-transition-sequence
           (SessionState -> (List TransitionEvent) -> TransitionResult))
  (define (validate-transition-sequence initial-state events)
    "Apply a sequence of transitions, returning the final state or first denial.
     Total: handles empty list (returns initial state)."
    (match events
      ((Nil) (TransitionOk initial-state))
      ((Cons ev rest)
       (match (transition initial-state ev)
         ((TransitionOk next-state)
          (validate-transition-sequence next-state rest))
         ((TransitionDenied reason)
          (TransitionDenied reason))))))

  ;; ─── Transition Count ───

  (declare count-valid-transitions
           (SessionState -> (List TransitionEvent) -> Integer))
  (define (count-valid-transitions initial-state events)
    "Count how many transitions in a sequence succeed before denial or end.
     Total: returns 0 for empty list."
    (match events
      ((Nil) 0)
      ((Cons ev rest)
       (match (transition initial-state ev)
         ((TransitionOk next-state)
          (+ 1 (count-valid-transitions next-state rest)))
         ((TransitionDenied _) 0)))))

  ;; ─── Canonical Lifecycle Paths ───

  (declare happy-path-events (Unit -> (List TransitionEvent)))
  (define (happy-path-events _u)
    "The canonical happy-path lifecycle: Creating → Active → Idle → Active → Closing → Closed."
    (make-list EvInitialized
               EvIdleTimeout
               EvMessageReceived
               EvShutdownRequested
               EvShutdownComplete))

  (declare error-path-events (Unit -> (List TransitionEvent)))
  (define (error-path-events _u)
    "Error lifecycle: Creating → Active → Error → restart → Creating."
    (make-list EvInitialized
               EvFatalError
               EvRestart)))
