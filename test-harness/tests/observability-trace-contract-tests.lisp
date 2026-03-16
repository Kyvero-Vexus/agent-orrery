;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; observability-trace-contract-tests.lisp — Tests for trace contract module
;;;
;;; Bead: agent-orrery-eb0.6.6

(in-package #:orrery/harness-tests)

(define-test observability-trace-contract-tests)

;;; ─── Obligation construction ───

(define-test (observability-trace-contract-tests obligation-construction)
  (let ((obl (orrery/adapter:make-trace-obligation
              :event-kind :session
              :source-tag :adapter
              :min-count 3
              :description "test obligation")))
    (is eq :session (orrery/adapter:tobl-event-kind obl))
    (is eq :adapter (orrery/adapter:tobl-source-tag obl))
    (is = 3 (orrery/adapter:tobl-min-count obl))
    (is string= "test obligation" (orrery/adapter:tobl-description obl))))

;;; ─── Contract construction ───

(define-test (observability-trace-contract-tests tui-contract-construction)
  (let ((c (orrery/adapter:make-tui-contract)))
    (is string= "tui-observability-v1" (orrery/adapter:tc-name c))
    (is eq :tui (orrery/adapter:tc-target c))
    (is = 5 (length (orrery/adapter:tc-obligations c)))
    (is = 1 (orrery/adapter:tc-version c))))

(define-test (observability-trace-contract-tests web-contract-has-probe)
  (let* ((c (orrery/adapter:make-web-contract))
         (kinds (mapcar #'orrery/adapter:tobl-event-kind
                        (orrery/adapter:tc-obligations c))))
    (is eq :web (orrery/adapter:tc-target c))
    (true (member :probe kinds :test #'eq))))

(define-test (observability-trace-contract-tests mcclim-contract-core-only)
  (let ((c (orrery/adapter:make-mcclim-contract)))
    (is eq :mcclim (orrery/adapter:tc-target c))
    (is = 4 (length (orrery/adapter:tc-obligations c)))))

;;; ─── Collector operations ───

(define-test (observability-trace-contract-tests collector-empty)
  (let ((col (orrery/adapter:make-empty-collector)))
    (is = 0 (orrery/adapter:tcol-count col))
    (is eq nil (orrery/adapter:tcol-streams col))))

(define-test (observability-trace-contract-tests collector-register-and-get)
  (let* ((col (orrery/adapter:make-empty-collector))
         (stream (orrery/adapter:make-trace-stream
                  :events nil :count 0))
         (col2 (orrery/adapter:collector-register-stream col :tui stream)))
    (is = 1 (orrery/adapter:tcol-count col2))
    (true (orrery/adapter:collector-get-stream col2 :tui))
    (false (orrery/adapter:collector-get-stream col2 :web))))

(define-test (observability-trace-contract-tests collector-replaces-existing)
  (let* ((col (orrery/adapter:make-empty-collector))
         (s1 (orrery/adapter:make-trace-stream :events nil :count 0))
         (s2 (orrery/adapter:make-trace-stream :events nil :count 0))
         (col2 (orrery/adapter:collector-register-stream col :tui s1))
         (col3 (orrery/adapter:collector-register-stream col2 :tui s2)))
    (is = 1 (orrery/adapter:tcol-count col3))
    (is eq s2 (orrery/adapter:collector-get-stream col3 :tui))))

;;; ─── Obligation checking ───

(define-test (observability-trace-contract-tests obligation-satisfied)
  (let* ((obl (orrery/adapter:make-trace-obligation
               :event-kind :session :source-tag :adapter :min-count 1))
         (ev (orrery/adapter:canonicalize-event :adapter :session 1000 "test"))
         (stream (orrery/adapter:make-trace-stream :events (list ev) :count 1))
         (result (orrery/adapter:check-obligation obl stream)))
    (is eq :satisfied (orrery/adapter:obr-verdict result))
    (is = 1 (orrery/adapter:obr-actual-count result))))

(define-test (observability-trace-contract-tests obligation-violated)
  (let* ((obl (orrery/adapter:make-trace-obligation
               :event-kind :cron :source-tag :adapter :min-count 2))
         (stream (orrery/adapter:make-trace-stream :events nil :count 0))
         (result (orrery/adapter:check-obligation obl stream)))
    (is eq :violated (orrery/adapter:obr-verdict result))
    (is = 0 (orrery/adapter:obr-actual-count result))))

(define-test (observability-trace-contract-tests obligation-exceeded)
  (let* ((obl (orrery/adapter:make-trace-obligation
               :event-kind :health :source-tag :adapter :min-count 1))
         (events (loop :for i :from 0 :below 20
                       :collect (orrery/adapter:canonicalize-event
                                 :adapter :health (+ 1000 i)
                                 (format nil "health-~D" i))))
         (stream (orrery/adapter:make-trace-stream
                  :events events :count (length events)))
         (result (orrery/adapter:check-obligation obl stream)))
    (is eq :exceeded (orrery/adapter:obr-verdict result))
    (is = 20 (orrery/adapter:obr-actual-count result))))

;;; ─── Contract verification ───

(define-test (observability-trace-contract-tests verify-all-satisfied)
  (let* ((events (list
                  (orrery/adapter:canonicalize-event :adapter :session 100 "s1")
                  (orrery/adapter:canonicalize-event :adapter :cron 101 "c1")
                  (orrery/adapter:canonicalize-event :adapter :health 102 "h1")
                  (orrery/adapter:canonicalize-event :adapter :alert 103 "a1")))
         (stream (orrery/adapter:make-trace-stream
                  :events events :count (length events)))
         (contract (orrery/adapter:make-mcclim-contract))
         (cv (orrery/adapter:verify-trace-contract contract stream 9999)))
    (true (orrery/adapter:cv-overall-pass-p cv))
    (is = 0 (orrery/adapter:cv-violated-count cv))
    (is = 4 (orrery/adapter:cv-satisfied-count cv))
    (is string= "mcclim-observability-v1" (orrery/adapter:cv-contract-name cv))))

(define-test (observability-trace-contract-tests verify-with-violations)
  (let* ((events (list
                  (orrery/adapter:canonicalize-event :adapter :session 100 "s1")))
         (stream (orrery/adapter:make-trace-stream
                  :events events :count (length events)))
         (contract (orrery/adapter:make-mcclim-contract))
         (cv (orrery/adapter:verify-trace-contract contract stream 9999)))
    (false (orrery/adapter:cv-overall-pass-p cv))
    (is = 1 (orrery/adapter:cv-satisfied-count cv))
    (is = 3 (orrery/adapter:cv-violated-count cv))))

;;; ─── Verify-all with collector ───

(define-test (observability-trace-contract-tests verify-all-missing-stream)
  (let* ((col (orrery/adapter:make-empty-collector))
         (contracts (list (orrery/adapter:make-tui-contract)))
         (results (orrery/adapter:verify-all-contracts col contracts 5000)))
    (is = 1 (length results))
    (false (orrery/adapter:cv-overall-pass-p (first results)))
    (is = 5 (orrery/adapter:cv-violated-count (first results)))))

(define-test (observability-trace-contract-tests verify-all-mixed)
  (let* ((core-events (list
                       (orrery/adapter:canonicalize-event :adapter :session 1 "s")
                       (orrery/adapter:canonicalize-event :adapter :cron 2 "c")
                       (orrery/adapter:canonicalize-event :adapter :health 3 "h")
                       (orrery/adapter:canonicalize-event :adapter :alert 4 "a")))
         (tui-events (append core-events
                             (list (orrery/adapter:canonicalize-event
                                    :adapter :lifecycle 5 "boot"))))
         (tui-stream (orrery/adapter:make-trace-stream
                      :events tui-events :count (length tui-events)))
         (web-stream (orrery/adapter:make-trace-stream
                      :events core-events :count (length core-events)))
         (col (orrery/adapter:collector-register-stream
               (orrery/adapter:collector-register-stream
                (orrery/adapter:make-empty-collector)
                :tui tui-stream)
               :web web-stream))
         (results (orrery/adapter:verify-all-contracts
                   col
                   (list (orrery/adapter:make-tui-contract)
                         (orrery/adapter:make-web-contract))
                   7000)))
    (is = 2 (length results))
    ;; TUI passes (all 5 obligations met)
    (true (orrery/adapter:cv-overall-pass-p (first results)))
    ;; Web fails (missing :probe event)
    (false (orrery/adapter:cv-overall-pass-p (second results)))))

;;; ─── Cross-UI parity matrix ───

(define-test (observability-trace-contract-tests parity-matrix-identical)
  (let* ((events (list
                  (orrery/adapter:canonicalize-event :adapter :session 1 "s")
                  (orrery/adapter:canonicalize-event :adapter :cron 2 "c")))
         (stream (orrery/adapter:make-trace-stream
                  :events events :count (length events)))
         (col (orrery/adapter:collector-register-stream
               (orrery/adapter:collector-register-stream
                (orrery/adapter:make-empty-collector)
                :tui stream)
               :web stream))
         (reports (orrery/adapter:cross-ui-parity-matrix col 8000)))
    (is = 1 (length reports))
    (true (orrery/adapter:parity-report-pass-p (first reports)))))

;;; ─── JSON serialization ───

(define-test (observability-trace-contract-tests obligation-result-json)
  (let* ((obl (orrery/adapter:make-trace-obligation
               :event-kind :session :source-tag :adapter :min-count 1))
         (ev (orrery/adapter:canonicalize-event :adapter :session 1000 "test"))
         (stream (orrery/adapter:make-trace-stream :events (list ev) :count 1))
         (result (orrery/adapter:check-obligation obl stream))
         (json (orrery/adapter:obligation-result->json result)))
    (true (search "\"verdict\":\"SATISFIED\"" json))
    (true (search "\"kind\":\"SESSION\"" json))))

(define-test (observability-trace-contract-tests contract-verification-json)
  (let* ((events (list
                  (orrery/adapter:canonicalize-event :adapter :session 100 "s")
                  (orrery/adapter:canonicalize-event :adapter :cron 101 "c")
                  (orrery/adapter:canonicalize-event :adapter :health 102 "h")
                  (orrery/adapter:canonicalize-event :adapter :alert 103 "a")))
         (stream (orrery/adapter:make-trace-stream
                  :events events :count (length events)))
         (cv (orrery/adapter:verify-trace-contract
              (orrery/adapter:make-mcclim-contract) stream 9999))
         (json (orrery/adapter:contract-verification->json cv)))
    (true (search "\"pass\":true" json))
    (true (search "\"contract\":\"mcclim-observability-v1\"" json))
    (true (search "\"satisfied\":4" json))))

;;; ─── Standard contracts list ───

(define-test (observability-trace-contract-tests standard-contracts-coverage)
  (let ((targets (mapcar #'orrery/adapter:tc-target
                         orrery/adapter:*standard-trace-contracts*)))
    (true (member :tui targets :test #'eq))
    (true (member :web targets :test #'eq))
    (true (member :mcclim targets :test #'eq))
    (is = 3 (length targets))))
