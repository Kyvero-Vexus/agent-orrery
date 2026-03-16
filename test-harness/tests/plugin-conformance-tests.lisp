;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; plugin-conformance-tests.lisp — Tests for plugin conformance corpus runner
;;; Bead: agent-orrery-bmc

(in-package #:orrery/harness-tests)

(define-test plugin-conformance-suite

  (define-test default-corpus-has-mixed-cases
    (let ((corpus (orrery/plugin:make-default-plugin-conformance-corpus)))
      (true (>= (length corpus) 4))
      (true (find "plugin-sdk-positive-v1" corpus
                  :key #'orrery/plugin:pcc-case-id
                  :test #'string=))
      (true (find "plugin-sdk-negative-missing-handler" corpus
                  :key #'orrery/plugin:pcc-case-id
                  :test #'string=))))

  (define-test run-single-positive-case
    (let* ((case (first (orrery/plugin:make-default-plugin-conformance-corpus)))
           (result (orrery/plugin:run-conformance-case case)))
      (is eq :pass (orrery/plugin:pcr-verdict result))
      (is eq t (orrery/plugin:pcr-actual-valid-p result))
      (is = 0 (length (orrery/plugin:pcr-errors result)))))

  (define-test run-single-negative-case
    (let* ((corpus (orrery/plugin:make-default-plugin-conformance-corpus))
           (bad (find "plugin-sdk-negative-missing-handler"
                      corpus
                      :key #'orrery/plugin:pcc-case-id
                      :test #'string=))
           (result (orrery/plugin:run-conformance-case bad)))
      (is eq :pass (orrery/plugin:pcr-verdict result))
      (is eq nil (orrery/plugin:pcr-actual-valid-p result))
      (true (> (length (orrery/plugin:pcr-errors result)) 0))))

  (define-test strict-schema-finds-duplicates
    (let* ((case (orrery/plugin:make-plugin-conformance-case
                  :case-id "dup"
                  :plugin-name "dup.plugin"
                  :cards (list (orrery/plugin:make-card-definition
                                :name "same" :title "A"
                                :renderer (lambda (d s) (declare (ignore d)) (write-string "a" s))
                                :priority 10)
                               (orrery/plugin:make-card-definition
                                :name "same" :title "B"
                                :renderer (lambda (d s) (declare (ignore d)) (write-string "b" s))
                                :priority 11))
                  :expected-valid-p nil
                  :expected-error-fragments (list "Duplicate card name")))
           (errors (orrery/plugin:strict-schema-checks case)))
      (true (find "Duplicate card name" errors
                  :test (lambda (frag s) (search frag s))))))

  (define-test compatibility-check-emits-findings
    (let* ((case (orrery/plugin:make-plugin-conformance-case
                  :case-id "compat"
                  :plugin-name "compat.plugin"
                  :commands (list (orrery/plugin:make-command-definition
                                   :name "ok"
                                   :handler (lambda () t)
                                   :description "ok"))
                  :transformers (list (orrery/plugin:make-transformer-definition
                                       :name "xf"
                                       :input-type :vendor
                                       :output-type :vendor-output
                                       :transform-fn (lambda (x) x)))))
           (findings (orrery/plugin:compatibility-checks case)))
      (true (> (length findings) 0))))

  (define-test full-corpus-report
    (let* ((corpus (orrery/plugin:make-default-plugin-conformance-corpus :seed 7))
           (report (orrery/plugin:run-plugin-conformance-corpus corpus :seed 7 :generated-at 1234)))
      (is = (length corpus) (orrery/plugin:pcrep-total report))
      (is = 0 (orrery/plugin:pcrep-failed report))
      (is = (length corpus) (orrery/plugin:pcrep-passed report))
      (is = 7 (orrery/plugin:pcrep-seed report))
      (is = 1234 (orrery/plugin:pcrep-generated-at report))))

  (define-test report-json-shape
    (let* ((report (orrery/plugin:run-plugin-conformance-corpus
                    (orrery/plugin:make-default-plugin-conformance-corpus)
                    :seed 0
                    :generated-at 0))
           (json (orrery/plugin:conformance-report->json report)))
      (true (search "\"suite\":\"plugin-sdk-v1\"" json))
      (true (search "\"results\"" json))
      (true (search "\"failed\":0" json))))

  (define-test deterministic-command-string
    (let ((cmd (orrery/plugin:deterministic-conformance-command)))
      (true (search "sbcl" cmd))
      (true (search "ci/run-tests.lisp" cmd)))))
