;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
(in-package #:orrery/harness-tests)

(define-test tui-session-detail)

;;; ─── Test Helpers ───

(defun %mk-session-view (id agent model status tokens cost age)
  (let ((rec (orrery/domain:make-session-record
              :id id :agent-name agent :channel "test" :status status
              :model model :total-tokens tokens
              :estimated-cost-cents cost :created-at 0 :updated-at 0)))
    (orrery/provider:make-session-view
     :record rec :age-seconds age
     :cost-display (format nil "$~,2F" (/ cost 100.0))
     :token-display (format nil "~Dk" (floor tokens 1000)))))

(defun %mk-event (id kind source ts)
  (orrery/domain:make-event-record
   :id id :kind kind :source source :timestamp ts
   :message ""))

;;; ─── Filter Tests ───

(define-test (tui-session-detail filter-match-text)
  (let ((spec (orrery/tui:make-filter-spec :text-query "alpha"))
        (view (%mk-session-view "s1" "alpha-agent" "gpt-4" :active 100 50 10)))
    (true (orrery/tui:match-filter-p spec view))))

(define-test (tui-session-detail filter-no-match-text)
  (let ((spec (orrery/tui:make-filter-spec :text-query "beta"))
        (view (%mk-session-view "s1" "alpha-agent" "gpt-4" :active 100 50 10)))
    (false (orrery/tui:match-filter-p spec view))))

(define-test (tui-session-detail filter-match-status)
  (let ((spec (orrery/tui:make-filter-spec :status-filter :active))
        (view (%mk-session-view "s1" "a" "m" :active 0 0 0)))
    (true (orrery/tui:match-filter-p spec view))))

(define-test (tui-session-detail filter-no-match-status)
  (let ((spec (orrery/tui:make-filter-spec :status-filter :closed))
        (view (%mk-session-view "s1" "a" "m" :active 0 0 0)))
    (false (orrery/tui:match-filter-p spec view))))

(define-test (tui-session-detail filter-match-model)
  (let ((spec (orrery/tui:make-filter-spec :model-filter "gpt"))
        (view (%mk-session-view "s1" "a" "gpt-4" :active 0 0 0)))
    (true (orrery/tui:match-filter-p spec view))))

(define-test (tui-session-detail filter-empty-matches-all)
  (let ((spec (orrery/tui:make-filter-spec))
        (view (%mk-session-view "s1" "a" "m" :active 0 0 0)))
    (true (orrery/tui:match-filter-p spec view))))

(define-test (tui-session-detail apply-filter-count)
  (let* ((spec (orrery/tui:make-filter-spec :text-query "alpha"))
         (v1 (%mk-session-view "s1" "alpha" "m" :active 0 0 0))
         (v2 (%mk-session-view "s2" "beta" "m" :active 0 0 0))
         (v3 (%mk-session-view "s3" "alpha-2" "m" :active 0 0 0))
         (result (orrery/tui:apply-filter spec (list v1 v2 v3))))
    (is = 3 (orrery/tui:fr-total-count result))
    (is = 2 (orrery/tui:fr-match-count result))))

(define-test (tui-session-detail sort-by-cost)
  (let* ((spec (orrery/tui:make-filter-spec :sort-key :cost))
         (v1 (%mk-session-view "s1" "a" "m" :active 0 10 0))
         (v2 (%mk-session-view "s2" "b" "m" :active 0 50 0))
         (result (orrery/tui:apply-filter spec (list v1 v2))))
    ;; v2 (50) should be first
    (is string= "s2"
        (orrery/domain:sr-id
         (orrery/provider:sv-record
          (first (orrery/tui:fr-matches result)))))))

;;; ─── History Tests ───

(define-test (tui-session-detail tail-history)
  (let* ((view (%mk-session-view "s1" "a" "m" :active 0 0 0))
         (e1 (%mk-event "e1" :session "s1" 100))
         (e2 (%mk-event "e2" :session "s1" 200))
         (e3 (%mk-event "e3" :session "s2" 300))
         (history (orrery/tui:tail-history view (list e1 e2 e3) 5)))
    (is = 2 (length history))
    ;; Most recent first
    (is = 200 (orrery/tui:he-timestamp (first history)))))

(define-test (tui-session-detail tail-history-limit)
  (let* ((view (%mk-session-view "s1" "a" "m" :active 0 0 0))
         (events (loop :for i :from 0 :below 20
                       :collect (%mk-event (format nil "e~D" i) :session "s1" (* i 10))))
         (history (orrery/tui:tail-history view events 5)))
    (is = 5 (length history))))

;;; ─── Build Detail ───

(define-test (tui-session-detail build-detail)
  (let* ((view (%mk-session-view "s1" "a" "m" :active 100 50 10))
         (e1 (%mk-event "e1" :session "s1" 100))
         (detail (orrery/tui:build-session-detail view (list e1) :count 5)))
    (is = 1 (orrery/tui:sd-history-count detail))
    (is eq view (orrery/tui:sd-view detail))))

;;; ─── Render Tests ───

(define-test (tui-session-detail render-detail-ops)
  (let* ((view (%mk-session-view "s1" "test-agent" "gpt-4" :active 1000 50 10))
         (e1 (%mk-event "e1" :session "s1" 100))
         (detail (orrery/tui:build-session-detail view (list e1)))
         (ops (orrery/tui:render-session-detail detail 0 0 80)))
    (true (> (length ops) 3))
    ;; First op should be header with session ID
    (true (search "s1" (orrery/tui:rop-text (first ops))))
    ;; Should have bold header
    (is eq :bold (orrery/tui:rop-attr (first ops)))))

(define-test (tui-session-detail render-filter-bar-ops)
  (let* ((spec (orrery/tui:make-filter-spec :text-query "test" :status-filter :active))
         (ops (orrery/tui:render-filter-bar spec 0 0 80)))
    (true (> (length ops) 1))
    ;; Should include "Filter:" label
    (true (search "Filter" (orrery/tui:rop-text (first ops))))))

(define-test (tui-session-detail render-empty-filter)
  (let* ((spec (orrery/tui:make-filter-spec))
         (ops (orrery/tui:render-filter-bar spec 0 0 80)))
    ;; Only the "Filter:" label, no filter chips
    (is = 1 (length ops))))
