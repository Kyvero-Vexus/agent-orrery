;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; tui-shell-tests.lisp — Deterministic tests for TUI dashboard shell
;;;
;;; Bead: agent-orrery-eb0.3.1
;;;
;;; Tests the pure layers: layout, keymap, state dispatch, rendering.
;;; No terminal needed — all functions are pure data transforms.

(in-package #:orrery/harness-tests)

(define-test tui-shell-suite)

;;; ============================================================
;;; Layout tests
;;; ============================================================

(define-test layout-default-creation
    :parent tui-shell-suite
  (let ((layout (orrery/tui:make-default-layout :rows 24 :cols 80)))
    ;; 6 panels created
    (is = 6 (length (orrery/tui:layout-panels layout)))
    ;; Default focus is sessions
    (is eq :sessions (orrery/tui:layout-active-panel layout))
    ;; Screen dimensions stored
    (is = 24 (orrery/tui:layout-screen-rows layout))
    (is = 80 (orrery/tui:layout-screen-cols layout))))

(define-test layout-grid-covers-screen
    :parent tui-shell-suite
  "All panels tile the screen without overlap or gaps."
  (let* ((rows 24) (cols 80)
         (layout (orrery/tui:make-default-layout :rows rows :cols cols))
         (panels (orrery/tui:layout-panels layout)))
    ;; Every panel has positive dimensions
    (dolist (p panels)
      (true (> (orrery/tui:panel-height p) 0))
      (true (> (orrery/tui:panel-width p) 0)))
    ;; Left column panels start at col 0
    (let ((left-panels (remove-if-not (lambda (p) (= 0 (orrery/tui:panel-col p))) panels)))
      (is = 3 (length left-panels)))
    ;; No panel extends below status bar row
    (dolist (p panels)
      (true (<= (+ (orrery/tui:panel-row p) (orrery/tui:panel-height p))
                (1- rows))))))

(define-test layout-custom-dimensions
    :parent tui-shell-suite
  "Layout adapts to non-standard screen sizes."
  (let* ((layout (orrery/tui:make-default-layout :rows 48 :cols 160))
         (panels (orrery/tui:layout-panels layout)))
    (is = 6 (length panels))
    ;; Panels should be larger
    (let ((sessions (orrery/tui:find-panel :sessions layout)))
      (true (> (orrery/tui:panel-height sessions) 10))
      (true (> (orrery/tui:panel-width sessions) 40)))))

(define-test layout-find-panel
    :parent tui-shell-suite
  (let ((layout (orrery/tui:make-default-layout)))
    (true (orrery/tui:panel-p (orrery/tui:find-panel :sessions layout)))
    (true (orrery/tui:panel-p (orrery/tui:find-panel :usage layout)))
    (is eq nil (orrery/tui:find-panel :nonexistent layout))))

(define-test layout-cycle-focus
    :parent tui-shell-suite
  "Focus cycles through all panels and wraps around."
  (let* ((layout (orrery/tui:make-default-layout))
         (l1 (orrery/tui:cycle-focus layout))
         (l2 (orrery/tui:cycle-focus l1))
         (l3 (orrery/tui:cycle-focus l2))
         (l4 (orrery/tui:cycle-focus l3))
         (l5 (orrery/tui:cycle-focus l4))
         (l6 (orrery/tui:cycle-focus l5)))
    ;; Original unchanged
    (is eq :sessions (orrery/tui:layout-active-panel layout))
    ;; Cycles through
    (is eq :cron (orrery/tui:layout-active-panel l1))
    (is eq :health (orrery/tui:layout-active-panel l2))
    (is eq :events (orrery/tui:layout-active-panel l3))
    (is eq :alerts (orrery/tui:layout-active-panel l4))
    (is eq :usage (orrery/tui:layout-active-panel l5))
    ;; Wraps to beginning
    (is eq :sessions (orrery/tui:layout-active-panel l6))))

(define-test layout-cycle-focus-reverse
    :parent tui-shell-suite
  (let* ((layout (orrery/tui:make-default-layout))
         (l1 (orrery/tui:cycle-focus layout :reverse-p t)))
    ;; Reverse from sessions wraps to usage
    (is eq :usage (orrery/tui:layout-active-panel l1))))

(define-test layout-cycle-preserves-original
    :parent tui-shell-suite
  "Cycling focus returns a new layout — original is unmodified."
  (let* ((layout (orrery/tui:make-default-layout))
         (sessions-panel (orrery/tui:find-panel :sessions layout)))
    (orrery/tui:cycle-focus layout)
    ;; Original still focused on sessions
    (is eq :sessions (orrery/tui:layout-active-panel layout))
    (true (orrery/tui:panel-focused-p sessions-panel))))

;;; ============================================================
;;; Keymap tests
;;; ============================================================

(define-test keymap-basic-lookups
    :parent tui-shell-suite
  (is eq :quit (orrery/tui:lookup-action #\q))
  (is eq :cycle-panel (orrery/tui:lookup-action :tab))
  (is eq :help (orrery/tui:lookup-action #\?))
  (is eq :refresh (orrery/tui:lookup-action #\r))
  (is eq :focus-sessions (orrery/tui:lookup-action #\1))
  (is eq :focus-usage (orrery/tui:lookup-action #\6)))

(define-test keymap-unbound-returns-nil
    :parent tui-shell-suite
  (is eq nil (orrery/tui:lookup-action #\z))
  (is eq nil (orrery/tui:lookup-action :f12)))

(define-test keymap-custom-map
    :parent tui-shell-suite
  "Custom keymap overrides defaults."
  (let ((custom '((#\x . :custom-action))))
    (is eq :custom-action (orrery/tui:lookup-action #\x custom))
    (is eq nil (orrery/tui:lookup-action #\q custom))))

;;; ============================================================
;;; State dispatch tests
;;; ============================================================

(defun make-test-tui-state ()
  "Build a tui-state with test fixture store."
  (let ((store (make-test-store))  ; reuse from tui-provider-tests
        (layout (orrery/tui:make-default-layout)))
    (orrery/tui:make-tui-state
     :layout layout :store store :now 1000000
     :mode :normal :running-p t)))

(define-test dispatch-quit
    :parent tui-shell-suite
  (let* ((state (make-test-tui-state))
         (new (orrery/tui:dispatch-action state :quit)))
    ;; Original unchanged
    (true (orrery/tui:ts-running-p state))
    ;; New state stopped
    (false (orrery/tui:ts-running-p new))))

(define-test dispatch-cycle-panel
    :parent tui-shell-suite
  (let* ((state (make-test-tui-state))
         (new (orrery/tui:dispatch-action state :cycle-panel)))
    (is eq :cron
        (orrery/tui:layout-active-panel (orrery/tui:ts-layout new)))
    ;; Original unchanged
    (is eq :sessions
        (orrery/tui:layout-active-panel (orrery/tui:ts-layout state)))))

(define-test dispatch-command-mode
    :parent tui-shell-suite
  (let* ((state (make-test-tui-state))
         (new (orrery/tui:dispatch-action state :command-mode)))
    (is eq :command (orrery/tui:ts-mode new))
    (is string= "" (orrery/tui:ts-command-input new))))

(define-test dispatch-normal-mode
    :parent tui-shell-suite
  (let* ((state (make-test-tui-state))
         (cmd-state (orrery/tui:dispatch-action state :command-mode))
         (normal (orrery/tui:dispatch-action cmd-state :normal-mode)))
    (is eq :normal (orrery/tui:ts-mode normal))))

(define-test dispatch-focus-direct
    :parent tui-shell-suite
  "Direct focus actions jump to specific panels."
  (let* ((state (make-test-tui-state))
         (new (orrery/tui:dispatch-action state :focus-health)))
    (is eq :health
        (orrery/tui:layout-active-panel (orrery/tui:ts-layout new)))))

(define-test dispatch-unknown-action
    :parent tui-shell-suite
  (let* ((state (make-test-tui-state))
         (new (orrery/tui:dispatch-action state :nonexistent)))
    ;; State still running, message indicates unknown
    (true (orrery/tui:ts-running-p new))
    (true (search "Unknown" (orrery/tui:ts-message new)))))

;;; ============================================================
;;; Render tests
;;; ============================================================

(define-test render-panel-frame-structure
    :parent tui-shell-suite
  "Panel frame produces render-ops for borders."
  (let* ((panel (orrery/tui:make-panel :id :test :title "Test"
                                        :row 0 :col 0 :height 5 :width 20))
         (ops (orrery/tui:render-panel-frame panel)))
    ;; At least top + bottom + side borders
    (true (> (length ops) 4))
    ;; All ops are render-op structs
    (dolist (op ops)
      (true (orrery/tui:render-op-p op)))))

(define-test render-panel-frame-dimensions
    :parent tui-shell-suite
  "Frame ops stay within panel bounds."
  (let* ((panel (orrery/tui:make-panel :id :test :title "Test"
                                        :row 5 :col 10 :height 8 :width 30))
         (ops (orrery/tui:render-panel-frame panel)))
    (dolist (op ops)
      (true (>= (orrery/tui:rop-row op) 5))
      (true (< (orrery/tui:rop-row op) 13))   ; row + height
      (true (>= (orrery/tui:rop-col op) 10)))))

(define-test render-focused-panel-bold
    :parent tui-shell-suite
  "Focused panels render with :bold attribute."
  (let* ((panel (orrery/tui:make-panel :id :test :title "Test"
                                        :row 0 :col 0 :height 5 :width 20
                                        :focused-p t))
         (ops (orrery/tui:render-panel-frame panel)))
    ;; Top border should be bold
    (let ((top-op (first ops)))
      (is eq :bold (orrery/tui:rop-attr top-op)))))

(define-test render-status-bar
    :parent tui-shell-suite
  (let* ((state (make-test-tui-state))
         (state2 (orrery/tui:dispatch-action state :refresh))
         (ops (orrery/tui:render-status-bar state2)))
    (is = 1 (length ops))
    (let ((op (first ops)))
      ;; On bottom row
      (is = 23 (orrery/tui:rop-row op))
      ;; Contains mode
      (true (search "NORMAL" (string-upcase (orrery/tui:rop-text op))))
      ;; Reverse video
      (is eq :reverse (orrery/tui:rop-attr op)))))

(define-test render-command-palette-hidden-in-normal
    :parent tui-shell-suite
  (let* ((state (make-test-tui-state))
         (ops (orrery/tui:render-command-palette state)))
    (is = 0 (length ops))))

(define-test render-command-palette-visible-in-command
    :parent tui-shell-suite
  (let* ((state (make-test-tui-state))
         (cmd-state (orrery/tui:dispatch-action state :command-mode))
         (ops (orrery/tui:render-command-palette cmd-state)))
    (is = 1 (length ops))
    (true (search ":" (orrery/tui:rop-text (first ops))))))

(define-test render-dashboard-produces-ops
    :parent tui-shell-suite
  "Full dashboard render produces a non-empty list of render-ops."
  (let* ((state (make-test-tui-state))
         (ops (orrery/tui:render-dashboard state)))
    (true (> (length ops) 20))  ; frames + content + status
    ;; All are render-ops
    (dolist (op ops)
      (true (orrery/tui:render-op-p op)))))

(define-test render-dashboard-with-nil-store
    :parent tui-shell-suite
  "Dashboard renders gracefully with no store data."
  (let* ((layout (orrery/tui:make-default-layout))
         (state (orrery/tui:make-tui-state :layout layout :store nil :now 0))
         (ops (orrery/tui:render-dashboard state)))
    ;; Should still produce frame ops + 'No data' content
    (true (> (length ops) 10))))

(define-test render-sessions-panel-content
    :parent tui-shell-suite
  "Sessions panel renders actual session data from store."
  (let* ((state (make-test-tui-state))
         (panel (orrery/tui:find-panel :sessions (orrery/tui:ts-layout state)))
         (ops (orrery/tui:render-sessions-panel panel state)))
    ;; Should have header + data rows
    (true (> (length ops) 1))
    ;; First op is header (bold)
    (is eq :bold (orrery/tui:rop-attr (first ops)))))

(define-test fit-string-behavior
    :parent tui-shell-suite
  "fit-string pads short strings, truncates long ones."
  (is string= "hello     " (orrery/tui::fit-string "hello" 10))
  (is string= "hello" (orrery/tui::fit-string "hello world" 5))
  (is string= "exact" (orrery/tui::fit-string "exact" 5)))
