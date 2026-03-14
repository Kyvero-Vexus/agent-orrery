;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; interface-matrix-tests.lisp — Tests for interface capability matrix

(in-package #:orrery/harness-tests)

(define-test interface-matrix-tests)

;;; ─── Fixture conformant matrix → ready ───

(define-test (interface-matrix-tests fixture-all-ready)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (cm (orrery/adapter:build-conformance-matrix harness))
         (im (orrery/adapter:generate-interface-matrix cm)))
    (is = 3 (length (orrery/adapter:im-packets im)))
    (true (plusp (orrery/adapter:im-adapter-coverage-pct im)))))

(define-test (interface-matrix-tests fixture-has-shared-fixtures)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (cm (orrery/adapter:build-conformance-matrix harness))
         (im (orrery/adapter:generate-interface-matrix cm)))
    (true (plusp (length (orrery/adapter:im-shared-fixtures im))))
    (true (member "health" (orrery/adapter:im-shared-fixtures im) :test #'string=))))

(define-test (interface-matrix-tests fixture-tui-packet)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (cm (orrery/adapter:build-conformance-matrix harness))
         (im (orrery/adapter:generate-interface-matrix cm))
         (tui (find :tui (orrery/adapter:im-packets im)
                    :key #'orrery/adapter:wp-interface-kind)))
    (true (not (null tui)))
    (is string= "epic-3" (orrery/adapter:wp-epic-id tui))
    (true (plusp (length (orrery/adapter:wp-kickoff-checklist tui))))))

(define-test (interface-matrix-tests fixture-web-packet)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (cm (orrery/adapter:build-conformance-matrix harness))
         (im (orrery/adapter:generate-interface-matrix cm))
         (web (find :web (orrery/adapter:im-packets im)
                    :key #'orrery/adapter:wp-interface-kind)))
    (is string= "epic-4" (orrery/adapter:wp-epic-id web))))

(define-test (interface-matrix-tests fixture-mcclim-packet)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (cm (orrery/adapter:build-conformance-matrix harness))
         (im (orrery/adapter:generate-interface-matrix cm))
         (mc (find :mcclim (orrery/adapter:im-packets im)
                   :key #'orrery/adapter:wp-interface-kind)))
    (is string= "epic-5" (orrery/adapter:wp-epic-id mc))))

;;; ─── Empty conformance → needs adapter ───

(define-test (interface-matrix-tests empty-needs-adapter)
  (let* ((cm (orrery/adapter:make-conformance-matrix))
         (im (orrery/adapter:generate-interface-matrix cm)))
    (true (every (lambda (p)
                   (member (orrery/adapter:wp-readiness p)
                           '(:needs-adapter :needs-fixture)))
                 (orrery/adapter:im-packets im)))))

(define-test (interface-matrix-tests empty-has-missing-caps)
  (let* ((cm (orrery/adapter:make-conformance-matrix))
         (im (orrery/adapter:generate-interface-matrix cm))
         (tui (find :tui (orrery/adapter:im-packets im)
                    :key #'orrery/adapter:wp-interface-kind)))
    (true (plusp (length (orrery/adapter:wp-missing-capabilities tui))))))

(define-test (interface-matrix-tests empty-coverage-zero)
  (let* ((cm (orrery/adapter:make-conformance-matrix))
         (im (orrery/adapter:generate-interface-matrix cm)))
    (is = 0 (orrery/adapter:im-adapter-coverage-pct im))))

;;; ─── JSON output ───

(define-test (interface-matrix-tests json-structure)
  (let* ((target (orrery/adapter:make-runtime-target
                  :profile :fixture :description "test"))
         (harness (orrery/adapter:run-contract-harness
                   target orrery/adapter:*standard-contracts*))
         (cm (orrery/adapter:build-conformance-matrix harness))
         (im (orrery/adapter:generate-interface-matrix cm))
         (json (orrery/adapter:interface-matrix-to-json im)))
    (true (search "\"adapter_coverage_pct\":" json))
    (true (search "\"packets\":[" json))
    (true (search "\"interface\":\"tui\"" json))
    (true (search "\"interface\":\"web\"" json))
    (true (search "\"interface\":\"mcclim\"" json))))

(define-test (interface-matrix-tests json-empty-conformance)
  (let* ((cm (orrery/adapter:make-conformance-matrix))
         (im (orrery/adapter:generate-interface-matrix cm))
         (json (orrery/adapter:interface-matrix-to-json im)))
    (true (search "\"adapter_coverage_pct\":0" json))
    (true (search "\"missing\":[" json))))
