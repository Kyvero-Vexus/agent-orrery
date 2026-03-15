;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; render.lisp — Pure rendering: tui-state → render-op lists
;;;
;;; Bead: agent-orrery-eb0.3.1
;;;
;;; Render-ops are typed structs: (row col text attr). No terminal I/O.
;;; The shell layer translates render-ops into actual croatoan calls.

(in-package #:orrery/tui)

;;; ============================================================
;;; Render operation struct
;;; ============================================================

(defstruct (render-op (:conc-name rop-))
  "A single positioned text output instruction."
  (row  0   :type fixnum)
  (col  0   :type fixnum)
  (text ""  :type string)
  (attr nil :type (or null keyword)))  ; :bold :reverse :dim nil

;;; ============================================================
;;; Panel frame rendering
;;; ============================================================

(declaim (ftype (function (panel) list) render-panel-frame))
(defun render-panel-frame (panel)
  "Render the box frame and title for a panel. Returns render-op list."
  (let* ((r (panel-row panel))
         (c (panel-col panel))
         (h (panel-height panel))
         (w (panel-width panel))
         (title (panel-title panel))
         (focused (panel-focused-p panel))
         (attr (if focused :bold nil))
         (ops '()))
    ;; Top border with title
    (let ((top-line (with-output-to-string (s)
                      (write-char #\+ s)
                      (write-char #\- s)
                      (write-string (subseq title 0 (min (length title) (- w 4))) s)
                      (loop repeat (max 0 (- w 3 (min (length title) (- w 4))))
                            do (write-char #\- s))
                      (write-char #\+ s))))
      (push (make-render-op :row r :col c
                            :text (subseq top-line 0 (min (length top-line) w))
                            :attr attr)
            ops))
    ;; Side borders for interior rows
    (loop for row-i from (1+ r) below (+ r h -1)
          do (push (make-render-op :row row-i :col c :text "|" :attr attr) ops)
             (push (make-render-op :row row-i :col (+ c w -1) :text "|" :attr attr) ops))
    ;; Bottom border
    (let ((bottom (make-string w :initial-element #\-)))
      (setf (char bottom 0) #\+
            (char bottom (1- w)) #\+)
      (push (make-render-op :row (+ r h -1) :col c :text bottom :attr attr) ops))
    (nreverse ops)))

;;; ============================================================
;;; Utility: truncate/pad string to width
;;; ============================================================

(declaim (ftype (function (string fixnum) string) fit-string))
(defun fit-string (str width)
  "Truncate or right-pad STR to exactly WIDTH characters."
  (let ((len (length str)))
    (cond
      ((= len width) str)
      ((> len width) (subseq str 0 width))
      (t (concatenate 'string str (make-string (- width len) :initial-element #\Space))))))

;;; ============================================================
;;; Per-panel renderers (pure: state → render-ops)
;;; ============================================================

(defun %render-table-panel (panel header rows)
  "Generic table renderer. HEADER is a string, ROWS is list of strings.
   Returns render-ops filling the panel interior."
  (let* ((r (panel-row panel))
         (c (panel-col panel))
         (w (panel-width panel))
         (h (panel-height panel))
         (inner-w (- w 2))  ; inside borders
         (inner-start-r (1+ r))
         (inner-start-c (1+ c))
         (ops '()))
    ;; Header row
    (when (> h 2)
      (push (make-render-op :row inner-start-r :col inner-start-c
                            :text (fit-string header inner-w)
                            :attr :bold)
            ops))
    ;; Data rows
    (loop for row-str in rows
          for i from (1+ inner-start-r)
          while (< i (+ r h -1))
          do (push (make-render-op :row i :col inner-start-c
                                   :text (fit-string row-str inner-w)
                                   :attr nil)
                   ops))
    (nreverse ops)))

(declaim (ftype (function (panel tui-state) list) render-sessions-panel))
(defun render-sessions-panel (panel state)
  "Render session list inside panel."
  (let* ((store (ts-store state))
         (now (ts-now state)))
    (if (null store)
        (%render-table-panel panel "No data" '())
        (let* ((page (query-sessions store :now now :limit (- (panel-height panel) 3)))
               (header "ID       Agent    Ch   Status")
               (rows (mapcar
                      (lambda (sv)
                        (let ((rec (sv-record sv)))
                          (format nil "~8A ~8A ~4A ~A"
                                  (subseq (sr-id rec) 0 (min 8 (length (sr-id rec))))
                                  (subseq (sr-agent-name rec) 0
                                          (min 8 (length (sr-agent-name rec))))
                                  (subseq (string (sr-channel rec)) 0
                                          (min 4 (length (string (sr-channel rec)))))
                                  (sr-status rec))))
                      (page-items page))))
          (%render-table-panel panel header rows)))))

(declaim (ftype (function (panel tui-state) list) render-cron-panel))
(defun render-cron-panel (panel state)
  "Render cron job list inside panel."
  (let ((store (ts-store state))
        (now (ts-now state)))
    (if (null store)
        (%render-table-panel panel "No data" '())
        (let* ((page (query-cron-jobs store :now now :limit (- (panel-height panel) 3)))
               (header "Name         Status  Interval")
               (rows (mapcar
                      (lambda (cv)
                        (let ((rec (cv-record cv)))
                          (format nil "~12A ~7A ~A"
                                  (subseq (cr-name rec) 0
                                          (min 12 (length (cr-name rec))))
                                  (cr-status rec)
                                  (cv-interval-display cv))))
                      (page-items page))))
          (%render-table-panel panel header rows)))))

(declaim (ftype (function (panel tui-state) list) render-health-panel))
(defun render-health-panel (panel state)
  "Render health status inside panel."
  (let ((store (ts-store state)))
    (if (null store)
        (%render-table-panel panel "No data" '())
        (let* ((page (query-health store))
               (header "Component   Status   ms")
               (rows (mapcar
                      (lambda (hv)
                        (let ((rec (hv-record hv)))
                          (format nil "~11A ~8A ~A"
                                  (subseq (hr-component rec) 0
                                          (min 11 (length (hr-component rec))))
                                  (hr-status rec)
                                  (hv-latency-display hv))))
                      (page-items page))))
          (%render-table-panel panel header rows)))))

(declaim (ftype (function (panel tui-state) list) render-events-panel))
(defun render-events-panel (panel state)
  "Render event tail inside panel."
  (let ((store (ts-store state))
        (now (ts-now state)))
    (if (null store)
        (%render-table-panel panel "No data" '())
        (let* ((page (query-events store :now now :limit (- (panel-height panel) 3)))
               (header "Kind     Source     Age")
               (rows (mapcar
                      (lambda (ev)
                        (let ((rec (ev-record ev)))
                          (format nil "~8A ~10A ~A"
                                  (er-kind rec)
                                  (subseq (er-source rec) 0
                                          (min 10 (length (er-source rec))))
                                  (format-age (ev-age-seconds ev)))))
                      (page-items page))))
          (%render-table-panel panel header rows)))))

(declaim (ftype (function (panel tui-state) list) render-alerts-panel))
(defun render-alerts-panel (panel state)
  "Render alert list inside panel."
  (let ((store (ts-store state))
        (now (ts-now state)))
    (if (null store)
        (%render-table-panel panel "No data" '())
        (let* ((page (query-alerts store :now now :limit (- (panel-height panel) 3)))
               (header "Sev  Title          Age")
               (rows (mapcar
                      (lambda (av)
                        (let ((rec (alv-record av)))
                          (format nil "~4A ~14A ~A"
                                  (ar-severity rec)
                                  (subseq (ar-title rec) 0
                                          (min 14 (length (ar-title rec))))
                                  (format-age (alv-age-seconds av)))))
                      (page-items page))))
          (%render-table-panel panel header rows)))))

(declaim (ftype (function (panel tui-state) list) render-usage-panel))
(defun render-usage-panel (panel state)
  "Render usage summary inside panel."
  (let ((store (ts-store state)))
    (if (null store)
        (%render-table-panel panel "No data" '())
        (let* ((page (query-usage store))
               (header "Model       Tokens    Cost")
               (rows (mapcar
                      (lambda (uv)
                        (let ((rec (uv-record uv)))
                          (format nil "~11A ~9A ~A"
                                  (subseq (ur-model rec) 0
                                          (min 11 (length (ur-model rec))))
                                  (uv-token-display uv)
                                  (uv-cost-display uv))))
                      (page-items page))))
          (%render-table-panel panel header rows)))))

;;; ============================================================
;;; Status bar + command palette
;;; ============================================================

(declaim (ftype (function (tui-state) list) render-status-bar))
(defun render-status-bar (state)
  "Render the bottom status bar. Returns render-op list."
  (let* ((lay (ts-layout state))
         (row (1- (layout-screen-rows lay)))
         (cols (layout-screen-cols lay))
         (mode-str (format nil "[~A]" (ts-mode state)))
         (msg (ts-message state))
         (line (fit-string (format nil "~A ~A" mode-str msg) cols)))
    (list (make-render-op :row row :col 0 :text line :attr :reverse))))

(declaim (ftype (function (tui-state) list) render-command-palette))
(defun render-command-palette (state)
  "Render command input line when in command mode."
  (if (eq (ts-mode state) :command)
      (let* ((lay (ts-layout state))
             (row (- (layout-screen-rows lay) 2))
             (cols (layout-screen-cols lay))
             (line (fit-string (format nil ":~A" (ts-command-input state)) cols)))
        (list (make-render-op :row row :col 0 :text line :attr :bold)))
      '()))

;;; ============================================================
;;; Full dashboard render
;;; ============================================================

(defparameter *panel-renderers*
  '((:sessions . render-sessions-panel)
    (:cron     . render-cron-panel)
    (:health   . render-health-panel)
    (:events   . render-events-panel)
    (:alerts   . render-alerts-panel)
    (:usage    . render-usage-panel))
  "Maps panel IDs to their render functions.")

(declaim (ftype (function (tui-state) list) render-dashboard))
(defun render-dashboard (state)
  "Render the entire dashboard. Returns a flat list of render-ops."
  (let ((ops '()))
    ;; Panel frames + content
    (dolist (panel (layout-panels (ts-layout state)))
      (setf ops (nconc ops (render-panel-frame panel)))
      (let ((renderer (cdr (assoc (panel-id panel) *panel-renderers*))))
        (when renderer
          (setf ops (nconc ops (funcall renderer panel state))))))
    ;; Command palette (if active)
    (setf ops (nconc ops (render-command-palette state)))
    ;; Status bar
    (setf ops (nconc ops (render-status-bar state)))
    ops))
