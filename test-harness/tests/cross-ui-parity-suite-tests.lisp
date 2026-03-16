;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cross-ui-parity-suite-tests.lisp — Tests for cross-UI parity suite
;;; Bead: agent-orrery-eb0.6.3

(in-package #:orrery/harness-tests)

(define-test cross-ui-parity-suite-tests)

(defun %mk-ev (source kind ts payload)
  (orrery/adapter:canonicalize-event source kind ts payload))

(defun %mk-tui-stream ()
  (orrery/adapter:canonicalize-stream
   (append
    (loop for i from 0 below 3 collect (%mk-ev :adapter :session (+ 100 i) (format nil "tui-session-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :cron (+ 110 i) (format nil "tui-cron-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :health (+ 120 i) (format nil "tui-health-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :alert (+ 130 i) (format nil "tui-alert-~D" i)))
    (list (%mk-ev :adapter :lifecycle 140 "tui-lifecycle")))))

(defun %mk-web-stream ()
  (orrery/adapter:canonicalize-stream
   (append
    (loop for i from 0 below 3 collect (%mk-ev :adapter :session (+ 200 i) (format nil "web-session-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :cron (+ 210 i) (format nil "web-cron-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :health (+ 220 i) (format nil "web-health-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :alert (+ 230 i) (format nil "web-alert-~D" i)))
    (list (%mk-ev :adapter :probe 240 "web-probe")))))

(defun %mk-mcclim-stream ()
  (orrery/adapter:canonicalize-stream
   (append
    (loop for i from 0 below 3 collect (%mk-ev :adapter :session (+ 300 i) (format nil "clim-session-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :cron (+ 310 i) (format nil "clim-cron-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :health (+ 320 i) (format nil "clim-health-~D" i)))
    (loop for i from 0 below 3 collect (%mk-ev :adapter :alert (+ 330 i) (format nil "clim-alert-~D" i))))))

(defun %mk-collector (&key (with-mcclim t))
  (let ((collector (orrery/adapter:make-empty-collector)))
    (setf collector (orrery/adapter:collector-register-stream collector :tui (%mk-tui-stream)))
    (setf collector (orrery/adapter:collector-register-stream collector :web (%mk-web-stream)))
    (if with-mcclim
        (orrery/adapter:collector-register-stream collector :mcclim (%mk-mcclim-stream))
        collector)))

(defun %mk-scenario (id status)
  (orrery/adapter:make-scenario-evidence :scenario-id id :status status :detail "ok"))

(defun %mk-artifact (kind &key (scenario-id "") (present-p t) (path "artifact"))
  (orrery/adapter:make-evidence-artifact
   :artifact-kind kind
   :scenario-id scenario-id
   :present-p present-p
   :path path
   :detail "ok"))

(defun %mk-web-manifest (&key (command "cd e2e && ./run-e2e.sh"))
  (let ((scenarios (loop for id in '("S1" "S2" "S3" "S4" "S5" "S6") collect (%mk-scenario id :pass)))
        (artifacts (append
                    (list (%mk-artifact :machine-report :path "web-report.json"))
                    (loop for id in '("S1" "S2" "S3" "S4" "S5" "S6")
                          append (list (%mk-artifact :screenshot :scenario-id id)
                                       (%mk-artifact :trace :scenario-id id))))))
    (orrery/adapter:make-runner-evidence-manifest
     :runner-id "web"
     :runner-kind :playwright-web
     :command command
     :scenarios scenarios
     :artifacts artifacts
     :timestamp 2000)))

(defun %mk-tui-manifest (&key (command "make e2e-tui"))
  (let ((scenarios (loop for id in '("T1" "T2" "T3" "T4" "T5" "T6") collect (%mk-scenario id :pass)))
        (artifacts (append
                    (list (%mk-artifact :machine-report :path "tui-report.json")
                          (%mk-artifact :asciicast :path "tui.cast"))
                    (loop for id in '("T1" "T2" "T3" "T4" "T5" "T6")
                          append (list (%mk-artifact :screenshot :scenario-id id)
                                       (%mk-artifact :transcript :scenario-id id))))))
    (orrery/adapter:make-runner-evidence-manifest
     :runner-id "tui"
     :runner-kind :mcp-tui-driver
     :command command
     :scenarios scenarios
     :artifacts artifacts
     :timestamp 2001)))

(define-test (cross-ui-parity-suite-tests full-pass)
  (let ((report (orrery/adapter:run-cross-ui-parity-suite
                 (%mk-collector)
                 :web-manifest (%mk-web-manifest)
                 :tui-manifest (%mk-tui-manifest)
                 :timestamp 3000)))
    (true (orrery/adapter:cuc-pass-p report))
    (is = 3 (orrery/adapter:cuc-required-target-count report))
    (is = 3 (orrery/adapter:cuc-passing-target-count report))))

(define-test (cross-ui-parity-suite-tests missing-mcclim-fails)
  (let* ((report (orrery/adapter:run-cross-ui-parity-suite
                  (%mk-collector :with-mcclim nil)
                  :web-manifest (%mk-web-manifest)
                  :tui-manifest (%mk-tui-manifest)
                  :timestamp 3001))
         (mcclim-row (find :mcclim (orrery/adapter:cuc-target-rows report)
                           :key #'orrery/adapter:tcr-target :test #'eq)))
    (false (orrery/adapter:cuc-pass-p report))
    (true mcclim-row)
    (false (orrery/adapter:tcr-contract-pass-p mcclim-row))))

(define-test (cross-ui-parity-suite-tests evidence-mismatch-fails-web)
  (let* ((report (orrery/adapter:run-cross-ui-parity-suite
                  (%mk-collector)
                  :web-manifest (%mk-web-manifest :command "npx playwright test")
                  :tui-manifest (%mk-tui-manifest)
                  :timestamp 3002))
         (web-row (find :web (orrery/adapter:cuc-target-rows report)
                        :key #'orrery/adapter:tcr-target :test #'eq)))
    (false (orrery/adapter:cuc-pass-p report))
    (true web-row)
    (false (orrery/adapter:tcr-evidence-pass-p web-row))))

(define-test (cross-ui-parity-suite-tests report-json-shape)
  (let* ((report (orrery/adapter:run-cross-ui-parity-suite
                  (%mk-collector)
                  :web-manifest (%mk-web-manifest)
                  :tui-manifest (%mk-tui-manifest)
                  :timestamp 3003))
         (json (orrery/adapter:cross-ui-conformance-report->json report)))
    (true (search "\"pass\":true" json))
    (true (search "\"required_targets\":3" json))
    (true (search "\"commands\"" json))
    (true (search "\"target\":\"web\"" json))))
