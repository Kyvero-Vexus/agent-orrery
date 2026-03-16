;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcclim-e2e-gate-tests.lisp — Tests for Epic-5 CLIM gate scenarios
;;; Bead: agent-orrery-eb0.5.5

(in-package #:orrery/harness-tests)

(define-test mcclim-e2e-gate-suite
  (define-test epic5-scenario-count
    (is = 6 (length (orrery/mcclim:run-epic5-scenarios))))

  (define-test epic5-all-pass
    (true (every #'orrery/mcclim:s5r-pass-p
                 (orrery/mcclim:run-epic5-scenarios))))

  (define-test epic5-json-shape
    (let ((json (orrery/mcclim:epic5-results->json
                 (orrery/mcclim:run-epic5-scenarios))))
      (true (search "\"suite\":\"epic5-clim-gate\"" json))
      (true (search "\"total\":6" json))
      (true (search "\"failed\":0" json))))

  (define-test epic5-s6-contains-quit-parity
    (let* ((results (orrery/mcclim:run-epic5-scenarios))
           (s6 (find "S6" results :key #'orrery/mcclim:s5r-id :test #'string=)))
      (true s6)
      (is eq t (orrery/mcclim:s5r-pass-p s6)))))
