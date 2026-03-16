;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; shell.lisp — Impure croatoan screen driver and event loop
;;;
;;; Bead: agent-orrery-eb0.3.1 (Phase 2)
;;;
;;; This is the ONLY impure file in orrery/tui. It:
;;;   1. Initializes croatoan (ncurses) screen
;;;   2. Runs the main event loop (input → dispatch → render → paint)
;;;   3. Handles terminal resize (SIGWINCH → relayout)
;;;   4. Wires live refresh via periodic store re-query
;;;
;;; All rendering logic is delegated to the pure render-op pipeline
;;; in render.lisp. This file only translates render-ops to ncurses calls.

(in-package #:orrery/tui)

;;; ============================================================
;;; Configuration
;;; ============================================================

(defparameter *refresh-interval-ms* 2000
  "Milliseconds between automatic data refresh cycles.")

(defparameter *input-timeout-ms* 100
  "Milliseconds to block waiting for input before checking refresh.")

;;; ============================================================
;;; Screen driver — translate render-ops to croatoan calls
;;; ============================================================

(declaim (ftype (function (t list) (values)) paint-render-ops))
(defun paint-render-ops (screen ops)
  "Paint a list of render-ops to the croatoan SCREEN. Impure."
  (dolist (op ops)
    (let ((row (rop-row op))
          (col (rop-col op))
          (text (rop-text op))
          (attr (rop-attr op)))
      ;; Bounds check — skip ops outside visible area
      (when (and (>= row 0)
                 (< row (croatoan:height screen))
                 (>= col 0)
                 (< col (croatoan:width screen)))
        (setf (croatoan:cursor-position screen) (list row col))
        (let ((max-len (- (croatoan:width screen) col)))
          (when (> (length text) max-len)
            (setq text (subseq text 0 max-len)))
          (case attr
            (:bold
             (setf (croatoan:attributes screen) '(:bold))
             (croatoan:add-string screen text)
             (setf (croatoan:attributes screen) '()))
            (:reverse
             (setf (croatoan:attributes screen) '(:reverse))
             (croatoan:add-string screen text)
             (setf (croatoan:attributes screen) '()))
            (:dim
             (setf (croatoan:attributes screen) '(:dim))
             (croatoan:add-string screen text)
             (setf (croatoan:attributes screen) '()))
            (otherwise
             (croatoan:add-string screen text)))))))
  (values))

;;; ============================================================
;;; Screen clear helper
;;; ============================================================

(declaim (ftype (function (t) (values)) clear-screen))
(defun clear-screen (screen)
  "Clear the entire screen. Impure."
  (croatoan:clear screen)
  (values))

;;; ============================================================
;;; Resize handling — detect new dimensions, recompute layout
;;; ============================================================

(declaim (ftype (function (t tui-state) tui-state) handle-resize))
(defun handle-resize (screen state)
  "Detect current screen dimensions and recompute layout if changed.
   Returns new tui-state (pure except for screen dimension query)."
  (let* ((new-rows (croatoan:height screen))
         (new-cols (croatoan:width screen))
         (lay (ts-layout state)))
    (if (and (= new-rows (layout-screen-rows lay))
             (= new-cols (layout-screen-cols lay)))
        state  ; no change
        (let ((new-layout (make-default-layout :rows new-rows :cols new-cols)))
          ;; Preserve active panel focus across resize
          (setf (layout-active-panel new-layout)
                (layout-active-panel lay))
          ;; Re-apply focus flags
          (dolist (p (layout-panels new-layout))
            (setf (panel-focused-p p)
                  (eq (panel-id p) (layout-active-panel new-layout))))
          (let ((new-state (copy-tui-state state)))
            (setf (ts-layout new-state) new-layout
                  (ts-message new-state)
                  (format nil "Resized: ~Dx~D" new-cols new-rows))
            new-state)))))

;;; ============================================================
;;; Live refresh — update store snapshot
;;; ============================================================

(declaim (ftype (function (tui-state &key (:refresh-fn (or null function)))
                          tui-state)
                refresh-store-data))
(defun refresh-store-data (state &key (refresh-fn nil))
  "Refresh the sync-store data in STATE. If REFRESH-FN is provided,
   call it to get a new sync-store. Returns updated tui-state.
   Impure when refresh-fn performs I/O."
  (if refresh-fn
      (let ((new-store (funcall refresh-fn (ts-store state))))
        (if new-store
            (let ((new-state (copy-tui-state state)))
              (setf (ts-store new-state) new-store
                    (ts-now new-state) (get-universal-time)
                    (ts-message new-state) "Data refreshed")
              new-state)
            ;; refresh-fn returned nil = no update available
            (let ((new-state (copy-tui-state state)))
              (setf (ts-now new-state) (get-universal-time))
              new-state)))
      ;; No refresh function — just update timestamp
      (let ((new-state (copy-tui-state state)))
        (setf (ts-now new-state) (get-universal-time))
        new-state)))

;;; ============================================================
;;; Input processing — translate croatoan events to actions
;;; ============================================================

(declaim (ftype (function (t) (or null keyword character)) read-input))
(defun read-input (screen)
  "Read a single input event from SCREEN with timeout.
   Returns a character or keyword, or NIL on timeout. Impure."
  (let ((event (croatoan:get-event screen)))
    event))

(declaim (ftype (function (tui-state (or null keyword character)) tui-state)
                process-input))
(defun process-input (state input)
  "Process a single INPUT event against STATE. Returns new tui-state.
   Pure — delegates to lookup-action and dispatch-action."
  (if (null input)
      state  ; timeout, no change
      (let ((action (lookup-action input)))
        (if action
            (dispatch-action state action)
            ;; In command mode, accumulate typed characters
            (if (and (eq (ts-mode state) :command)
                     (characterp input))
                (let ((new-state (copy-tui-state state)))
                  (cond
                    ;; Backspace
                    ((or (char= input #\Backspace)
                         (char= input #\Rubout))
                     (let ((cmd (ts-command-input state)))
                       (setf (ts-command-input new-state)
                             (if (> (length cmd) 0)
                                 (subseq cmd 0 (1- (length cmd)))
                                 ""))))
                    ;; Enter — execute command
                    ((or (char= input #\Return)
                         (char= input #\Newline))
                     (setf (ts-message new-state)
                           (format nil "Command: ~A" (ts-command-input state))
                           (ts-mode new-state) :normal
                           (ts-command-input new-state) ""))
                    ;; Regular character
                    (t
                     (setf (ts-command-input new-state)
                           (concatenate 'string
                                        (ts-command-input state)
                                        (string input)))))
                  new-state)
                ;; Not in command mode, unbound key — ignore
                state)))))

;;; ============================================================
;;; Full render cycle — clear + paint
;;; ============================================================

(declaim (ftype (function (t tui-state) (values)) render-frame))
(defun render-frame (screen state)
  "Execute one full render cycle: clear, compute render-ops, paint. Impure."
  (clear-screen screen)
  (let ((ops (render-dashboard state)))
    (paint-render-ops screen ops))
  (croatoan:refresh screen)
  (values))

;;; ============================================================
;;; Main event loop
;;; ============================================================

(declaim (ftype (function (&key (:initial-store t)
                                (:refresh-fn (or null function))
                                (:refresh-interval-ms (or null fixnum)))
                          (values))
                run-tui))
(defun run-tui (&key (initial-store nil)
                     (refresh-fn nil)
                     (refresh-interval-ms *refresh-interval-ms*))
  "Start the TUI dashboard. Blocks until user quits.

   INITIAL-STORE — sync-store for initial data (or NIL for empty).
   REFRESH-FN — (lambda (old-store) -> new-store-or-nil) for live refresh.
                Called periodically to update data. May be NIL for static mode.
   REFRESH-INTERVAL-MS — milliseconds between refresh cycles.

   Impure: initializes terminal, runs event loop, restores terminal on exit."
  (croatoan:with-screen (screen :input-echoing nil
                                :input-blocking nil
                                :enable-function-keys t
                                :cursor-visible nil)
    ;; Set input timeout for non-blocking reads
    (setf (croatoan:input-blocking screen) nil)
    (let* ((rows (croatoan:height screen))
           (cols (croatoan:width screen))
           (layout (make-default-layout :rows rows :cols cols))
           (state (make-tui-state
                   :layout layout
                   :store initial-store
                   :now (get-universal-time)
                   :mode :normal
                   :running-p t))
           (last-refresh-time (get-internal-real-time))
           (refresh-interval-ticks
             (* (or refresh-interval-ms *refresh-interval-ms*)
                (/ internal-time-units-per-second 1000))))
      ;; Initial render
      (render-frame screen state)
      ;; Main loop
      (loop while (ts-running-p state) do
        ;; Read input (non-blocking)
        (let ((input (read-input screen)))
          (setq state (process-input state input)))
        ;; Check for resize
        (setq state (handle-resize screen state))
        ;; Periodic refresh
        (let ((now-ticks (get-internal-real-time)))
          (when (> (- now-ticks last-refresh-time) refresh-interval-ticks)
            (setq state (refresh-store-data state :refresh-fn refresh-fn))
            (setq last-refresh-time now-ticks)))
        ;; Render
        (render-frame screen state)
        ;; Small sleep to avoid burning CPU
        (sleep 0.05))))
  (values))

;;; ============================================================
;;; Convenience entry point
;;; ============================================================

(declaim (ftype (function (&key (:store t)
                                (:refresh-fn (or null function)))
                          (values))
                start-dashboard))
(defun start-dashboard (&key (store nil) (refresh-fn nil))
  "Convenience entry point for starting the TUI dashboard.

   STORE — initial sync-store snapshot.
   REFRESH-FN — optional function (old-store → new-store) for live updates.

   Example:
     (start-dashboard :store (snapshot-from-adapter my-adapter)
                      :refresh-fn (lambda (old) (snapshot-from-adapter my-adapter)))"
  (run-tui :initial-store store :refresh-fn refresh-fn))
