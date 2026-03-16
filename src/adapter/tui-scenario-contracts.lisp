;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-scenario-contracts.lisp — Deterministic mcp-tui-driver scenario contracts
;;; Bead: agent-orrery-igw.1

(in-package #:orrery/adapter)

(deftype tui-scenario-id ()
  '(member :T1 :T2 :T3 :T4 :T5 :T6))

(defstruct (tui-scenario-contract (:conc-name tsc-))
  "Typed contract for one TUI E2E scenario."
  (id :T1 :type tui-scenario-id)
  (name "" :type string)
  (deterministic-command "make e2e-tui" :type string)
  (fixture-assumptions nil :type list)
  (required-artifacts '(:screenshot :transcript) :type list)
  (artifact-dir "test-results/tui-artifacts/" :type string))

(defparameter *tui-t1-t6-contracts*
  (list
   (make-tui-scenario-contract
    :id :T1
    :name "initial-load"
    :fixture-assumptions '(:fixture-store-populated :default-layout)
    :required-artifacts '(:screenshot :transcript :report :asciicast))
   (make-tui-scenario-contract
    :id :T2
    :name "panel-navigation"
    :fixture-assumptions '(:keymap-loaded :panel-focus-rules)
    :required-artifacts '(:screenshot :transcript))
   (make-tui-scenario-contract
    :id :T3
    :name "tab-cycle"
    :fixture-assumptions '(:keymap-loaded :tab-order-deterministic)
    :required-artifacts '(:screenshot :transcript))
   (make-tui-scenario-contract
    :id :T4
    :name "help-toggle"
    :fixture-assumptions '(:help-pane-available)
    :required-artifacts '(:screenshot :transcript))
   (make-tui-scenario-contract
    :id :T5
    :name "resize-handling"
    :fixture-assumptions '(:resize-events-enabled)
    :required-artifacts '(:screenshot :transcript))
   (make-tui-scenario-contract
    :id :T6
    :name "fixture-content"
    :fixture-assumptions '(:fixture-store-populated :deterministic-clock)
    :required-artifacts '(:screenshot :transcript)))
  "Canonical T1-T6 contracts for Epic 3 policy.")

(declaim
 (ftype (function () (values list &optional)) tui-scenario-contracts)
 (ftype (function () (values string &optional)) tui-deterministic-contract-command)
 (ftype (function (list) (values boolean &optional)) tui-contracts-cover-t1-t6-p)
 (ftype (function (list) (values list &optional)) missing-tui-contract-artifacts))

(defun tui-scenario-contracts ()
  "Return canonical T1-T6 contracts."
  (copy-list *tui-t1-t6-contracts*))

(defun tui-deterministic-contract-command ()
  "Deterministic command for T1-T6 contract execution."
  "make e2e-tui")

(defun tui-contracts-cover-t1-t6-p (contracts)
  "True when CONTRACTS contain every T1-T6 id exactly once."
  (let* ((ids (mapcar #'tsc-id contracts))
         (expected '(:T1 :T2 :T3 :T4 :T5 :T6)))
    (and (= (length ids) 6)
         (every (lambda (id) (member id ids :test #'eq)) expected)
         (= (length (remove-duplicates ids :test #'eq)) 6))))

(defun missing-tui-contract-artifacts (contracts)
  "Return alist of (scenario-id . missing-artifact-kinds) for empty artifact dirs.
Static contract checker only: validates required artifact declarations exist."
  (let ((result nil)
        (required '(:screenshot :transcript)))
    (dolist (c contracts)
      (let ((missing (remove-if (lambda (k) (member k (tsc-required-artifacts c) :test #'eq))
                                required)))
        (when missing
          (push (cons (tsc-id c) missing) result))))
    (nreverse result)))
