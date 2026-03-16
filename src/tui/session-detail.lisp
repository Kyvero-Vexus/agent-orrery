;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; session-detail.lisp — TUI session drill-down, history, filtering
;;;
;;; Bead: agent-orrery-eb0.3.2
;;; Pure functional — no terminal I/O.

(in-package #:orrery/tui)

;;; ─── Filter Types ───

(deftype sort-key ()
  '(member :timestamp :cost :tokens :name))

(defstruct (filter-spec (:conc-name fs-))
  "Search/filter criteria for session list."
  (text-query    nil :type (or null string))
  (status-filter nil :type (or null keyword))
  (model-filter  nil :type (or null string))
  (sort-key :timestamp :type sort-key))

(defstruct (filter-result (:conc-name fr-))
  "Result of applying a filter to sessions."
  (matches nil :type list)
  (total-count 0 :type fixnum)
  (match-count 0 :type fixnum)
  (applied-filters nil :type list))

;;; ─── History Entry ───

(defstruct (history-entry (:conc-name he-))
  "A single entry in the session history tail."
  (timestamp 0 :type fixnum)
  (event-kind :session :type keyword)
  (summary "" :type string))

;;; ─── Session Detail ───

(defstruct (session-detail (:conc-name sd-))
  "Expanded session view for drill-down."
  (view nil :type t)
  (history nil :type list)
  (history-count 0 :type fixnum)
  (filter nil :type (or null filter-spec)))

;;; ─── Filter Matching ───

(declaim (ftype (function (filter-spec t) (values boolean &optional))
                match-filter-p))
(defun match-filter-p (spec view)
  "Test if a session-view matches filter criteria. Pure."
  (declare (optimize (safety 3)))
  (let ((record (sv-record view)))
    (and
     ;; Text query: match against agent-name
     (or (null (fs-text-query spec))
         (not (null (search (string-upcase (fs-text-query spec))
                            (string-upcase (sr-agent-name record))))))
     ;; Status filter
     (or (null (fs-status-filter spec))
         (eq (fs-status-filter spec) (sr-status record)))
     ;; Model filter
     (or (null (fs-model-filter spec))
         (not (null (search (string-upcase (fs-model-filter spec))
                            (string-upcase (sr-model record)))))))))

;;; ─── Apply Filter ───

(declaim (ftype (function (filter-spec list) (values filter-result &optional))
                apply-filter))
(defun apply-filter (spec views)
  "Filter session views by criteria. Pure."
  (declare (optimize (safety 3)))
  (let* ((total (length views))
         (matches (remove-if-not (lambda (v) (match-filter-p spec v)) views))
         (sorted (sort-sessions matches (fs-sort-key spec)))
         (filters (remove nil
                          (list (when (fs-text-query spec)
                                  (list :text (fs-text-query spec)))
                                (when (fs-status-filter spec)
                                  (list :status (fs-status-filter spec)))
                                (when (fs-model-filter spec)
                                  (list :model (fs-model-filter spec)))))))
    (make-filter-result
     :matches sorted
     :total-count total
     :match-count (length sorted)
     :applied-filters filters)))

;;; ─── Sorting ───

(declaim (ftype (function (list sort-key) (values list &optional))
                sort-sessions))
(defun sort-sessions (views sort-key)
  "Sort session views by key. Pure."
  (declare (optimize (safety 3)))
  (let ((copy (copy-list views)))
    (sort copy
          (ecase sort-key
            (:timestamp (lambda (a b)
                          (> (sv-age-seconds a) (sv-age-seconds b))))
            (:cost (lambda (a b)
                     (> (sr-estimated-cost-cents (sv-record a))
                        (sr-estimated-cost-cents (sv-record b)))))
            (:tokens (lambda (a b)
                       (> (sr-total-tokens (sv-record a))
                          (sr-total-tokens (sv-record b)))))
            (:name (lambda (a b)
                     (string< (sr-agent-name (sv-record a))
                              (sr-agent-name (sv-record b)))))))))

;;; ─── History Tail ───

(declaim (ftype (function (t list fixnum) (values list &optional))
                tail-history))
(defun tail-history (session-view events count)
  "Extract last N history entries for a session. Pure."
  (declare (optimize (safety 3)))
  (let* ((record (sv-record session-view))
         (sid (sr-id record))
         (matching (remove-if-not
                    (lambda (ev) (string= sid (er-source ev)))
                    events))
         (sorted (sort (copy-list matching)
                       (lambda (a b)
                         (> (er-timestamp a) (er-timestamp b)))))
         (tail (subseq sorted 0 (min count (length sorted)))))
    (mapcar (lambda (ev)
              (make-history-entry
               :timestamp (er-timestamp ev)
               :event-kind (er-kind ev)
               :summary (format nil "~A: ~A" (er-kind ev) (er-source ev))))
            tail)))

;;; ─── Build Detail ───

(declaim (ftype (function (t list &key (:count fixnum) (:filter (or null filter-spec)))
                          (values session-detail &optional))
                build-session-detail))
(defun build-session-detail (session-view events &key (count 10) filter)
  "Build session detail for drill-down. Pure."
  (declare (optimize (safety 3)))
  (let ((history (tail-history session-view events count)))
    (make-session-detail
     :view session-view
     :history history
     :history-count (length history)
     :filter filter)))

;;; ─── Render Detail ───

(declaim (ftype (function (session-detail fixnum fixnum fixnum)
                          (values list &optional))
                render-session-detail))
(defun render-session-detail (detail start-row start-col width)
  "Render session detail pane as render-ops. Pure."
  (declare (optimize (safety 3)))
  (let* ((view (sd-view detail))
         (record (sv-record view))
         (ops nil)
         (row start-row))
    ;; Header
    (push (make-render-op :row row :col start-col
                          :text (format nil "Session: ~A" (sr-id record))
                          :attr :bold)
          ops)
    (incf row)
    ;; Agent/model
    (push (make-render-op :row row :col start-col
                          :text (format nil "Agent: ~A  Model: ~A"
                                        (sr-agent-name record) (sr-model record))
                          :attr :normal)
          ops)
    (incf row)
    ;; Status/cost
    (push (make-render-op :row row :col start-col
                          :text (format nil "Status: ~A  Cost: ~A  Tokens: ~A"
                                        (sr-status record)
                                        (sv-cost-display view)
                                        (sv-token-display view))
                          :attr :normal)
          ops)
    (incf row 2)
    ;; History
    (push (make-render-op :row row :col start-col
                          :text (format nil "History (~D entries):" (sd-history-count detail))
                          :attr :bold)
          ops)
    (incf row)
    (dolist (entry (sd-history detail))
      (push (make-render-op :row row :col (+ start-col 2)
                            :text (format nil "[~D] ~A"
                                          (he-timestamp entry) (he-summary entry))
                            :attr :dim)
            ops)
      (incf row))
    ;; width used for future truncation
    (when nil width)
    (nreverse ops)))

;;; ─── Render Filter Bar ───

(declaim (ftype (function (filter-spec fixnum fixnum fixnum)
                          (values list &optional))
                render-filter-bar))
(defun render-filter-bar (spec row col width)
  "Render filter bar as render-ops. Pure."
  (declare (optimize (safety 3))
           (ignore width))
  (let ((parts nil))
    (push (make-render-op :row row :col col
                          :text "Filter:"
                          :attr :bold)
          parts)
    (when (fs-text-query spec)
      (push (make-render-op :row row :col (+ col 8)
                            :text (format nil "text:\"~A\"" (fs-text-query spec))
                            :attr :highlight)
            parts))
    (when (fs-status-filter spec)
      (push (make-render-op :row row :col (+ col 30)
                            :text (format nil "status:~A" (fs-status-filter spec))
                            :attr :highlight)
            parts))
    (when (fs-model-filter spec)
      (push (make-render-op :row row :col (+ col 50)
                            :text (format nil "model:\"~A\"" (fs-model-filter spec))
                            :attr :highlight)
            parts))
    (nreverse parts)))
