;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; test-cross-ui-parity-v2.lisp — Cross-UI parity assertions for v2 Coalton modules
;;; Bead: agent-orrery-3scj (eb0.9.4)
;;;
;;; Verifies that all 3 UIs (TUI, Web, McCLIM) expose the same data
;;; contracts for v2 Coalton modules (cost-optimizer, capacity-planner,
;;; session-analytics, audit-trail).

(in-package #:orrery/harness-tests)

(define-test cross-ui-parity-v2)

;;; ─── TUI v2 Module Symbols ───

(define-test (cross-ui-parity-v2 tui-cost-optimizer-card-exists)
  (let ((pkg (find-package "ORRERY/TUI")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "BUILD-COST-OPTIMIZER-CARD" pkg)
      (true present-p)
      (true (fboundp sym)))))

(define-test (cross-ui-parity-v2 tui-capacity-planner-card-exists)
  (let ((pkg (find-package "ORRERY/TUI")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "BUILD-CAPACITY-PLANNER-CARD" pkg)
      (true present-p)
      (true (fboundp sym)))))

;;; ─── Web v2 Module Symbols ───

(define-test (cross-ui-parity-v2 web-audit-trail-html-exists)
  (let ((pkg (find-package "ORRERY/WEB")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "RENDER-AUDIT-TRAIL-HTML" pkg)
      (true present-p)
      (true (fboundp sym)))))

(define-test (cross-ui-parity-v2 web-analytics-html-exists)
  (let ((pkg (find-package "ORRERY/WEB")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "RENDER-ANALYTICS-HTML" pkg)
      (true present-p)
      (true (fboundp sym)))))

(define-test (cross-ui-parity-v2 web-audit-trail-json-exists)
  (let ((pkg (find-package "ORRERY/WEB")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "AUDIT-TRAIL-JSON" pkg)
      (true present-p)
      (true (fboundp sym)))))

(define-test (cross-ui-parity-v2 web-analytics-json-exists)
  (let ((pkg (find-package "ORRERY/WEB")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "ANALYTICS-JSON" pkg)
      (true present-p)
      (true (fboundp sym)))))

;;; ─── McCLIM v2 Module Symbols ───

(define-test (cross-ui-parity-v2 mcclim-cost-optimizer-pane-exists)
  (let ((pkg (find-package "ORRERY/MCCLIM")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "DISPLAY-COST-OPTIMIZER" pkg)
      (true present-p)
      (true (fboundp sym)))))

(define-test (cross-ui-parity-v2 mcclim-capacity-planner-pane-exists)
  (let ((pkg (find-package "ORRERY/MCCLIM")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "DISPLAY-CAPACITY-PLANNER" pkg)
      (true present-p)
      (true (fboundp sym)))))

(define-test (cross-ui-parity-v2 mcclim-session-analytics-pane-exists)
  (let ((pkg (find-package "ORRERY/MCCLIM")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "DISPLAY-SESSION-ANALYTICS" pkg)
      (true present-p)
      (true (fboundp sym)))))

(define-test (cross-ui-parity-v2 mcclim-audit-trail-pane-exists)
  (let ((pkg (find-package "ORRERY/MCCLIM")))
    (true pkg)
    (multiple-value-bind (sym present-p) (find-symbol "DISPLAY-AUDIT-TRAIL" pkg)
      (true present-p)
      (true (fboundp sym)))))

;;; ─── Cross-UI Contract Parity ───

(define-test (cross-ui-parity-v2 all-uis-pass-v2-module-check)
  "Verify that the cross-UI parity suite reports all 3 UIs as v2-module-pass."
  (let ((report (orrery/adapter:run-cross-ui-parity-suite
                 (%mk-collector)
                 :web-manifest (%mk-web-manifest)
                 :tui-manifest (%mk-tui-manifest)
                 :timestamp 5000)))
    (dolist (row (orrery/adapter:cuc-target-rows report))
      (true (orrery/adapter:tcr-v2-module-pass-p row))
      (is = 0 (orrery/adapter:tcr-v2-missing-count row)))))

(define-test (cross-ui-parity-v2 v2-module-count-per-ui)
  "Each UI has the expected number of v2 contract symbols."
  ;; TUI: 2 (cost-optimizer-card, capacity-planner-card)
  ;; Web: 4 (audit-trail-html, analytics-html, audit-trail-json, analytics-json)
  ;; McCLIM: 4 (cost-optimizer, capacity-planner, session-analytics, audit-trail)
  (is = 2 (length (orrery/adapter::%target-v2-symbol-contract :tui)))
  (is = 4 (length (orrery/adapter::%target-v2-symbol-contract :web)))
  (is = 4 (length (orrery/adapter::%target-v2-symbol-contract :mcclim))))

(define-test (cross-ui-parity-v2 json-report-contains-v2-fields)
  "JSON conformance report includes v2 module data."
  (let* ((report (orrery/adapter:run-cross-ui-parity-suite
                  (%mk-collector)
                  :web-manifest (%mk-web-manifest)
                  :tui-manifest (%mk-tui-manifest)
                  :timestamp 5001))
         (json (orrery/adapter:cross-ui-conformance-report->json report)))
    (true (search "v2_pass" json))
    (true (search "v2_missing" json))))
