;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cross-ui-evidence-verifier-tests.lisp — Tests for Playwright/mcp evidence verifier
;;;
;;; Bead: agent-orrery-ai0

(in-package #:orrery/harness-tests)

(define-test cross-ui-evidence-verifier-tests)

(defun %mk-scenario (id status)
  (orrery/adapter:make-scenario-evidence
   :scenario-id id
   :status status
   :detail "test"))

(defun %mk-artifact (kind &key (scenario-id "") (present-p t) (path "artifact"))
  (orrery/adapter:make-evidence-artifact
   :scenario-id scenario-id
   :artifact-kind kind
   :present-p present-p
   :path path
   :detail "test"))

(defun %mk-web-manifest ()
  (let ((scenarios (loop for id in '("S1" "S2" "S3" "S4" "S5" "S6")
                         collect (%mk-scenario id :pass)))
        (artifacts (append
                    (list (%mk-artifact :machine-report :path "e2e-report.json"))
                    (loop for id in '("S1" "S2" "S3" "S4" "S5" "S6")
                          append (list (%mk-artifact :screenshot :scenario-id id)
                                       (%mk-artifact :trace :scenario-id id))))))
    (orrery/adapter:make-runner-evidence-manifest
     :runner-id "web"
     :runner-kind :playwright-web
     :command "cd e2e && ./run-e2e.sh"
     :scenarios scenarios
     :artifacts artifacts
     :timestamp 1000)))

(defun %mk-tui-manifest ()
  (let ((scenarios (loop for id in '("T1" "T2" "T3" "T4" "T5" "T6")
                         collect (%mk-scenario id :pass)))
        (artifacts (append
                    (list (%mk-artifact :machine-report :path "tui-results.json")
                          (%mk-artifact :asciicast :path "session.cast"))
                    (loop for id in '("T1" "T2" "T3" "T4" "T5" "T6")
                          append (list (%mk-artifact :screenshot :scenario-id id)
                                       (%mk-artifact :transcript :scenario-id id))))))
    (orrery/adapter:make-runner-evidence-manifest
     :runner-id "tui"
     :runner-kind :mcp-tui-driver
     :command "make e2e-tui"
     :scenarios scenarios
     :artifacts artifacts
     :timestamp 1001)))

(define-test (cross-ui-evidence-verifier-tests normalize-scenario-id)
  (is string= "S1" (orrery/adapter:normalize-scenario-id "S1: dashboard loads"))
  (is string= "T4" (orrery/adapter:normalize-scenario-id "T4")))

(define-test (cross-ui-evidence-verifier-tests verify-runner-pass)
  (let ((report (orrery/adapter:verify-runner-evidence
                 (%mk-web-manifest)
                 orrery/adapter:*default-web-scenarios*
                 orrery/adapter:*web-required-artifacts*
                 '(:machine-report)
                 orrery/adapter:*expected-web-command*)))
    (true (orrery/adapter:ecr-pass-p report))
    (is = 6 (orrery/adapter:ecr-required-scenarios-covered report))
    (is = 0 (length (orrery/adapter:ecr-findings report)))))

(define-test (cross-ui-evidence-verifier-tests missing-global-artifact-fails)
  (let* ((manifest (%mk-tui-manifest))
         (manifest2 (orrery/adapter:make-runner-evidence-manifest
                     :runner-id (orrery/adapter:rem-runner-id manifest)
                     :runner-kind (orrery/adapter:rem-runner-kind manifest)
                     :command (orrery/adapter:rem-command manifest)
                     :scenarios (orrery/adapter:rem-scenarios manifest)
                     :artifacts (remove :asciicast
                                        (orrery/adapter:rem-artifacts manifest)
                                        :key #'orrery/adapter:ea-artifact-kind)
                     :timestamp (orrery/adapter:rem-timestamp manifest)))
         (report (orrery/adapter:verify-runner-evidence
                  manifest2
                  orrery/adapter:*default-tui-scenarios*
                  orrery/adapter:*tui-required-artifacts*
                  '(:machine-report :asciicast)
                  orrery/adapter:*expected-tui-command*)))
    (false (orrery/adapter:ecr-pass-p report))
    (true (plusp (length (orrery/adapter:ecr-findings report))))))

(define-test (cross-ui-evidence-verifier-tests command-mismatch-fails)
  (let* ((manifest (%mk-web-manifest))
         (manifest2 (orrery/adapter:make-runner-evidence-manifest
                     :runner-id (orrery/adapter:rem-runner-id manifest)
                     :runner-kind (orrery/adapter:rem-runner-kind manifest)
                     :command "npx playwright test"
                     :scenarios (orrery/adapter:rem-scenarios manifest)
                     :artifacts (orrery/adapter:rem-artifacts manifest)
                     :timestamp (orrery/adapter:rem-timestamp manifest)))
         (report (orrery/adapter:verify-runner-evidence
                  manifest2
                  orrery/adapter:*default-web-scenarios*
                  orrery/adapter:*web-required-artifacts*
                  '(:machine-report)
                  orrery/adapter:*expected-web-command*)))
    (false (orrery/adapter:ecr-pass-p report))
    (true (find "deterministic-command-mismatch"
                (orrery/adapter:ecr-findings report)
                :key #'orrery/adapter:ef-code
                :test #'string=))))

(define-test (cross-ui-evidence-verifier-tests parity-mismatch-detected)
  (let* ((web (%mk-web-manifest))
         (tui (%mk-tui-manifest))
         (tui-scenarios (copy-list (orrery/adapter:rem-scenarios tui)))
         (bad-scenarios (cons (%mk-scenario "T3" :fail)
                              (remove "T3" tui-scenarios
                                      :key #'orrery/adapter:sce-scenario-id
                                      :test #'string=)))
         (bad-tui (orrery/adapter:make-runner-evidence-manifest
                   :runner-id "tui"
                   :runner-kind :mcp-tui-driver
                   :command "make e2e-tui"
                   :scenarios bad-scenarios
                   :artifacts (orrery/adapter:rem-artifacts tui)
                   :timestamp 1002))
         (web-report (orrery/adapter:verify-runner-evidence
                      web
                      orrery/adapter:*default-web-scenarios*
                      orrery/adapter:*web-required-artifacts*
                      '(:machine-report)
                      orrery/adapter:*expected-web-command*))
         (tui-report (orrery/adapter:verify-runner-evidence
                      bad-tui
                      orrery/adapter:*default-tui-scenarios*
                      orrery/adapter:*tui-required-artifacts*
                      '(:machine-report :asciicast)
                      orrery/adapter:*expected-tui-command*))
         (parity (orrery/adapter:build-evidence-parity-report web-report tui-report)))
    (false (orrery/adapter:epr-pass-p parity))
    (true (> (orrery/adapter:epr-mismatch-count parity) 0))))

(define-test (cross-ui-evidence-verifier-tests full-cross-ui-pass)
  (let ((report (orrery/adapter:verify-cross-ui-evidence
                 (%mk-web-manifest)
                 (%mk-tui-manifest)
                 :timestamp 2000)))
    (true (orrery/adapter:cuer-pass-p report))
    (is = 6 (orrery/adapter:epr-match-count
             (orrery/adapter:cuer-parity-report report)))))

(define-test (cross-ui-evidence-verifier-tests json-serialization)
  (let* ((report (orrery/adapter:verify-cross-ui-evidence
                  (%mk-web-manifest)
                  (%mk-tui-manifest)
                  :timestamp 3000))
         (json (orrery/adapter:cross-ui-evidence-report->json report)))
    (true (search "\"pass\":true" json))
    (true (search "\"parity\"" json))
    (true (search "\"web\"" json))))
