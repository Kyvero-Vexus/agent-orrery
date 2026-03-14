;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; preflight-tests.lisp — Tests for preflight + gate runner + JSON emitter

(in-package #:orrery/harness-tests)

(define-test preflight-tests)

;;; ─── Preflight core (cne) ───

(define-test (preflight-tests compute-overall-pass)
  (let ((checks (list (orrery/adapter:make-preflight-check
                        :name "a" :status :pass :message "ok")
                       (orrery/adapter:make-preflight-check
                        :name "b" :status :pass :message "ok"))))
    (is eq :pass (orrery/adapter:compute-overall-status checks))))

(define-test (preflight-tests compute-overall-fail)
  (let ((checks (list (orrery/adapter:make-preflight-check
                        :name "a" :status :pass :message "ok")
                       (orrery/adapter:make-preflight-check
                        :name "b" :status :fail :message "bad"))))
    (is eq :fail (orrery/adapter:compute-overall-status checks))))

(define-test (preflight-tests compute-overall-warn)
  (let ((checks (list (orrery/adapter:make-preflight-check
                        :name "a" :status :pass :message "ok")
                       (orrery/adapter:make-preflight-check
                        :name "b" :status :warn :message "hmm"))))
    (is eq :warn (orrery/adapter:compute-overall-status checks))))

(define-test (preflight-tests run-preflight-returns-report)
  (let ((report (orrery/adapter:run-preflight "http://localhost:18789"
                                               '("/health" "/sessions"))))
    (true (orrery/adapter:preflight-report-p report))
    (is = 2 (length (orrery/adapter:pr-checks report)))
    (true (member (orrery/adapter:pr-overall-status report)
                  '(:pass :fail :warn :skip)))))

(define-test (preflight-tests sexp-serialization)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "t1" :status :pass :message "ok"))
                  :overall-status :pass :timestamp 100 :adapter-name "test"))
         (sexp (orrery/adapter:preflight-report-to-sexp report)))
    (true (stringp sexp))
    (true (search ":PASS" sexp))
    (true (search "t1" sexp))))

;;; ─── Gate runner (id9) ───

(define-test (preflight-tests gate-all-pass)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "endpoint:/health" :status :pass :message "ok"))
                  :overall-status :pass :timestamp 0 :adapter-name "t"))
         (result (orrery/adapter:apply-failure-policies report '())))
    (true (orrery/adapter:gr-gate-passed-p result))
    (is = 0 (orrery/adapter:gr-exit-code result))))

(define-test (preflight-tests gate-hard-fail)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "endpoint:/health" :status :fail :message "down"))
                  :overall-status :fail :timestamp 0 :adapter-name "t"))
         (policies (list (orrery/adapter:make-failure-policy
                          :check-name "endpoint:/health"
                          :action :hard-fail
                          :rationale "Required")))
         (result (orrery/adapter:apply-failure-policies report policies)))
    (false (orrery/adapter:gr-gate-passed-p result))
    (is = 1 (orrery/adapter:gr-exit-code result))
    (is = 1 (length (orrery/adapter:gr-applied-policies result)))))

(define-test (preflight-tests gate-soft-fail)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "endpoint:/sessions" :status :fail :message "down"))
                  :overall-status :fail :timestamp 0 :adapter-name "t"))
         (policies (list (orrery/adapter:make-failure-policy
                          :check-name "endpoint:/sessions"
                          :action :soft-fail
                          :rationale "Optional")))
         (result (orrery/adapter:apply-failure-policies report policies)))
    (true (orrery/adapter:gr-gate-passed-p result))
    (is = 2 (orrery/adapter:gr-exit-code result))))

(define-test (preflight-tests gate-skip-policy)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "endpoint:/unknown" :status :fail :message "?"))
                  :overall-status :fail :timestamp 0 :adapter-name "t"))
         (policies (list (orrery/adapter:make-failure-policy
                          :check-name "endpoint:/unknown"
                          :action :skip
                          :rationale "Not critical")))
         (result (orrery/adapter:apply-failure-policies report policies)))
    (true (orrery/adapter:gr-gate-passed-p result))
    (is = 0 (orrery/adapter:gr-exit-code result))))

(define-test (preflight-tests gate-default-policy-hard-fails)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "endpoint:/novel" :status :fail :message "?"))
                  :overall-status :fail :timestamp 0 :adapter-name "t"))
         (result (orrery/adapter:apply-failure-policies report '())))
    ;; No explicit policy → default hard-fail
    (false (orrery/adapter:gr-gate-passed-p result))
    (is = 1 (orrery/adapter:gr-exit-code result))))

(define-test (preflight-tests run-gate-integration)
  (let ((result (orrery/adapter:run-gate "http://localhost:18789" '("/health"))))
    (true (orrery/adapter:gate-result-p result))
    (true (orrery/adapter:preflight-report-p (orrery/adapter:gr-report result)))))

;;; ─── JSON emitter (apd) ───

(define-test (preflight-tests json-report-structure)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "endpoint:/health" :status :pass :message "ok"))
                  :overall-status :pass :timestamp 1000 :adapter-name "test"))
         (json (orrery/adapter:preflight-report-to-json report)))
    (true (stringp json))
    (true (search "\"adapter_name\":" json))
    (true (search "\"overall_status\":\"pass\"" json))
    (true (search "\"checks\":[" json))
    (true (search "\"name\":\"endpoint:/health\"" json))
    (true (search "\"status\":\"pass\"" json))))

(define-test (preflight-tests json-gate-result-structure)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks '() :overall-status :pass :timestamp 0 :adapter-name "t"))
         (gate (orrery/adapter:make-gate-result
                :gate-passed-p t :applied-policies '() :report report :exit-code 0))
         (json (orrery/adapter:gate-result-to-json gate)))
    (true (stringp json))
    (true (search "\"gate_passed\":true" json))
    (true (search "\"exit_code\":0" json))
    (true (search "\"applied_policies\":[]" json))
    (true (search "\"report\":" json))))

(define-test (preflight-tests json-escaping)
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "test" :status :fail
                                  :message "has \"quotes\" and \\backslash"))
                  :overall-status :fail :timestamp 0 :adapter-name "t"))
         (json (orrery/adapter:preflight-report-to-json report)))
    (true (search "\\\"quotes\\\"" json))
    (true (search "\\\\" json))))

(define-test (preflight-tests json-deterministic)
  ;; Same input produces identical output
  (let* ((report (orrery/adapter:make-preflight-report
                  :checks (list (orrery/adapter:make-preflight-check
                                  :name "a" :status :pass :message "ok")
                                (orrery/adapter:make-preflight-check
                                  :name "b" :status :fail :message "bad"))
                  :overall-status :fail :timestamp 42 :adapter-name "det"))
         (json1 (orrery/adapter:preflight-report-to-json report))
         (json2 (orrery/adapter:preflight-report-to-json report)))
    (is string= json1 json2)))

(define-test (preflight-tests json-gate-with-policies)
  (let* ((gate (orrery/adapter:make-gate-result
                :gate-passed-p nil
                :applied-policies (list (orrery/adapter:make-failure-policy
                                          :check-name "endpoint:/health"
                                          :action :hard-fail
                                          :rationale "Required"))
                :report nil :exit-code 1))
         (json (orrery/adapter:gate-result-to-json gate)))
    (true (search "\"gate_passed\":false" json))
    (true (search "\"action\":\"hard-fail\"" json))
    (true (search "\"rationale\":\"Required\"" json))))
