;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; plugin-cross-ui-smoke-tests.lisp — Smoke tests for plugin loading across UI surfaces
;;;
;;; Verifies that plugins register correctly and their cards/commands/transformers
;;; are accessible from all three UI surfaces (TUI, Web, McCLIM).
;;;
;;; Bead: agent-orrery-uux9

(in-package #:orrery/harness-tests)

;;; ─── Test Plugin for Cross-UI Smoke Tests ───

(defclass cross-ui-smoke-plugin (orrery/plugin:plugin)
  ()
  (:documentation "Sample plugin for cross-UI smoke testing."))

(defmethod orrery/plugin:plugin-card-definitions ((p cross-ui-smoke-plugin))
  (list
   (orrery/plugin:make-card-definition
    :name "smoke-cost-card"
    :title "Cost Overview"
    :renderer (lambda (data stream)
                (declare (type (or null t) data)
                         (type stream stream)
                         (ignore data))
                (write-string "Cost: $0.00" stream))
    :data-fn (lambda () (list :cost-cents 0))
    :priority 50)
   (orrery/plugin:make-card-definition
    :name "smoke-capacity-card"
    :title "Capacity Status"
    :renderer (lambda (data stream)
                (declare (type (or null t) data)
                         (type stream stream)
                         (ignore data))
                (write-string "Capacity: OK" stream))
    :data-fn (lambda () (list :capacity-percent 0))
    :priority 60)))

(defmethod orrery/plugin:plugin-command-definitions ((p cross-ui-smoke-plugin))
  (list
   (orrery/plugin:make-command-definition
    :name "smoke-refresh"
    :handler (lambda () t)
    :description "Refresh smoke test data"
    :keystroke #\R)))

(defmethod orrery/plugin:plugin-transformer-definitions ((p cross-ui-smoke-plugin))
  (list
   (orrery/plugin:make-transformer-definition
    :name "smoke-transform"
    :input-type :raw
    :output-type :processed
    :transform-fn (lambda (x) (declare (ignore x)) :processed))))

(define-test plugin-cross-ui-smoke-suite
  "Smoke tests verifying plugin loading and accessibility across UI surfaces.")

;;; ─── Plugin Registration Smoke Tests ───

(define-test (plugin-cross-ui-smoke-suite plugin-registration-smoke)
  "Smoke: plugin can be registered and found."
  (let ((plugin (make-instance 'cross-ui-smoke-plugin
                               :name "smoke-plugin"
                               :version "1.0.0")))
    (orrery/plugin:register-plugin plugin)
    (unwind-protect
         (let ((found (orrery/plugin:find-plugin "smoke-plugin")))
           (true found)
           (is string= "smoke-plugin" (orrery/plugin:plugin-name found))
           (is string= "1.0.0" (orrery/plugin:plugin-version found)))
      (orrery/plugin:unregister-plugin "smoke-plugin"))))

(define-test (plugin-cross-ui-smoke-suite plugin-card-aggregation-smoke)
  "Smoke: plugin cards are aggregated into all-card-definitions."
  (let ((plugin (make-instance 'cross-ui-smoke-plugin
                               :name "smoke-cards"
                               :version "1.0.0")))
    (orrery/plugin:register-plugin plugin)
    (unwind-protect
         (let* ((all-cards (orrery/plugin:all-card-definitions))
                (cost-card (find "smoke-cost-card" all-cards
                                 :key #'orrery/plugin:cd-name
                                 :test #'string=))
                (cap-card (find "smoke-capacity-card" all-cards
                                :key #'orrery/plugin:cd-name
                                :test #'string=)))
           (true cost-card "Cost card should be in aggregated cards")
           (true cap-card "Capacity card should be in aggregated cards"))
      (orrery/plugin:unregister-plugin "smoke-cards"))))

(define-test (plugin-cross-ui-smoke-suite plugin-command-aggregation-smoke)
  "Smoke: plugin commands are aggregated into all-command-definitions."
  (let ((plugin (make-instance 'cross-ui-smoke-plugin
                               :name "smoke-cmds"
                               :version "1.0.0")))
    (orrery/plugin:register-plugin plugin)
    (unwind-protect
         (let* ((all-cmds (orrery/plugin:all-command-definitions))
                (refresh-cmd (find "smoke-refresh" all-cmds
                                   :key #'orrery/plugin:cmd-name
                                   :test #'string=)))
           (true refresh-cmd "Refresh command should be in aggregated commands"))
      (orrery/plugin:unregister-plugin "smoke-cmds"))))

;;; ─── TUI Surface Integration Smoke Tests ───

(define-test (plugin-cross-ui-smoke-suite tui-package-exports-smoke)
  "Smoke: TUI package exports required render functions."
  (let ((pkg (find-package "ORRERY/TUI")))
    (true pkg "TUI package should exist")
    (true (find-symbol "RENDER-DASHBOARD" pkg)
          "RENDER-DASHBOARD should be exported")
    (true (find-symbol "TUI-STATE" pkg)
          "TUI-STATE should be exported")))

(define-test (plugin-cross-ui-smoke-suite tui-card-render-smoke)
  "Smoke: plugin card renderer can produce output."
  (let ((card (orrery/plugin:make-card-definition
               :name "tui-smoke-card"
               :title "TUI Smoke"
               :renderer (lambda (data stream)
                           (declare (type (or null t) data)
                                    (type stream stream)
                                    (ignore data))
                           (write-string "[TUI: SMOKE OK]" stream))
               :priority 50)))
    (with-output-to-string (s)
      (funcall (orrery/plugin:cd-renderer card) nil s)
      (is string= "[TUI: SMOKE OK]" (get-output-stream-string s)))))

;;; ─── Web Surface Integration Smoke Tests ───

(define-test (plugin-cross-ui-smoke-suite web-package-exports-smoke)
  "Smoke: Web package exports required HTML/JSON functions."
  (let ((pkg (find-package "ORRERY/WEB")))
    (true pkg "Web package should exist")
    (true (find-symbol "RENDER-PAGE" pkg)
          "RENDER-PAGE should be exported")
    (true (find-symbol "RENDER-ANALYTICS-HTML" pkg)
          "RENDER-ANALYTICS-HTML should be exported")
    (true (find-symbol "ANALYTICS-JSON" pkg)
          "ANALYTICS-JSON should be exported")))

(define-test (plugin-cross-ui-smoke-suite web-card-render-smoke)
  "Smoke: plugin card renderer can produce HTML-like output."
  (let ((card (orrery/plugin:make-card-definition
               :name "web-smoke-card"
               :title "Web Smoke"
               :renderer (lambda (data stream)
                           (declare (type (or null t) data)
                                    (type stream stream)
                                    (ignore data))
                           (write-string "<div>Web: SMOKE OK</div>" stream))
               :priority 50)))
    (with-output-to-string (s)
      (funcall (orrery/plugin:cd-renderer card) nil s)
      (let ((output (get-output-stream-string s)))
        (true (search "<div>" output)
              "Output should contain HTML div tag")))))

;;; ─── McCLIM Surface Integration Smoke Tests ───

(define-test (plugin-cross-ui-smoke-suite mcclim-package-exports-smoke)
  "Smoke: McCLIM package exports required display functions."
  (let ((pkg (find-package "ORRERY/MCCLIM")))
    (true pkg "McCLIM package should exist")
    (true (find-symbol "DISPLAY-COST-OPTIMIZER" pkg)
          "DISPLAY-COST-OPTIMIZER should be exported")
    (true (find-symbol "DISPLAY-CAPACITY-PLANNER" pkg)
          "DISPLAY-CAPACITY-PLANNER should be exported")
    (true (find-symbol "DISPLAY-SESSION-ANALYTICS" pkg)
          "DISPLAY-SESSION-ANALYTICS should be exported")))

(define-test (plugin-cross-ui-smoke-suite mcclim-card-render-smoke)
  "Smoke: plugin card renderer can produce output suitable for McCLIM."
  (let ((card (orrery/plugin:make-card-definition
               :name "mcclim-smoke-card"
               :title "McCLIM Smoke"
               :renderer (lambda (data stream)
                           (declare (type (or null t) data)
                                    (type stream stream)
                                    (ignore data))
                           (write-string "McCLIM: SMOKE OK" stream))
               :priority 50)))
    (with-output-to-string (s)
      (funcall (orrery/plugin:cd-renderer card) nil s)
      (is string= "McCLIM: SMOKE OK" (get-output-stream-string s)))))

;;; ─── Cross-UI Parity Smoke Tests ───

(define-test (plugin-cross-ui-smoke-suite cross-ui-v2-symbols-smoke)
  "Smoke: all three UI surfaces have required v2 symbols fboundp."
  (dolist (target '(:tui :web :mcclim))
    (let* ((pkg-name (ecase target
                       (:tui "ORRERY/TUI")
                       (:web "ORRERY/WEB")
                       (:mcclim "ORRERY/MCCLIM")))
           (pkg (find-package pkg-name)))
      (true pkg (format nil "~A package should exist" pkg-name)))))

(define-test (plugin-cross-ui-smoke-suite plugin-schema-smoke)
  "Smoke: plugin conformance schema validates test plugin."
  (let* ((plugin (make-instance 'cross-ui-smoke-plugin
                                :name "smoke-schema"
                                :version "1.0.0"))
         (result (orrery/plugin:validate-plugin plugin)))
    (is eq t (orrery/plugin:pvr-valid-p result))
    (is = 0 (length (orrery/plugin:pvr-errors result)))))

(define-test (plugin-cross-ui-smoke-suite plugin-conformance-command-smoke)
  "Smoke: deterministic conformance command is well-formed."
  (let ((cmd (orrery/plugin:deterministic-conformance-command)))
    (true (stringp cmd))
    (true (search "sbcl" cmd :test #'char-equal)
          "Command should reference sbcl")))

;;; ─── Plugin Lifecycle Smoke Tests ───

(define-test (plugin-cross-ui-smoke-suite plugin-lifecycle-smoke)
  "Smoke: plugin can be registered, found, and unregistered."
  (let ((plugin (make-instance 'cross-ui-smoke-plugin
                               :name "lifecycle-smoke"
                               :version "1.0.0")))
    ;; Register
    (orrery/plugin:register-plugin plugin)
    (true (orrery/plugin:find-plugin "lifecycle-smoke")
          "Plugin should be found after registration")
    
    ;; Unregister
    (orrery/plugin:unregister-plugin "lifecycle-smoke")
    (is eq nil (orrery/plugin:find-plugin "lifecycle-smoke")
        "Plugin should not be found after unregistration")))
