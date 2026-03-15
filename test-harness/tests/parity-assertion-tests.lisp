;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test parity-assertion)

(defun %ev (source kind ts payload)
  (canonicalize-event source kind ts payload))

(defun %stream (&rest events)
  (canonicalize-stream events))

(define-test (parity-assertion default-profile-shapes)
  (is string= "tui-strict" (ap-name *tui-parity-profile*))
  (is eq :web (ap-target *web-parity-profile*))
  (is eq :mcclim (ap-target *mcclim-parity-profile*))
  (is = 0 (tol-max-mismatches (ap-tolerance *tui-parity-profile*)))
  (is = 1 (tol-max-missing (ap-tolerance *web-parity-profile*))))

(define-test (parity-assertion filter-by-source)
  (let* ((s (%stream (%ev :adapter :session 1000 "a")
                     (%ev :pipeline :cron 1001 "b")
                     (%ev :store :health 1002 "c")))
         (f (filter-stream-by-sources s '(:adapter :store))))
    (is = 2 (ts-count f))
    (is eq :adapter (tev-source-tag (first (ts-events f))))
    (is eq :store (tev-source-tag (second (ts-events f))))))

(define-test (parity-assertion count-by-kind)
  (let* ((s (%stream (%ev :adapter :session 1000 "a")
                     (%ev :pipeline :session 1001 "b")
                     (%ev :store :health 1002 "c")))
         (counts (count-by-kind s)))
    (is = 2 (or (cdr (assoc :session counts :test #'eq)) 0))
    (is = 1 (or (cdr (assoc :health counts :test #'eq)) 0))))

(define-test (parity-assertion evaluate-required-kind-fails)
  (let* ((tol (make-tolerance-spec :max-mismatches 0
                                   :max-missing 2
                                   :required-kinds '(:session)))
         (entry (evaluate-kind-parity :session 2 1 tol)))
    (is eq :fail (ae-verdict entry))))

(define-test (parity-assertion evaluate-optional-kind-skips)
  (let* ((tol (make-tolerance-spec :max-mismatches 0
                                   :max-missing 2
                                   :required-kinds '(:session)))
         (entry (evaluate-kind-parity :probe 3 2 tol)))
    (is eq :skip (ae-verdict entry))))

(define-test (parity-assertion run-identical-pass)
  (let* ((s1 (%stream (%ev :adapter :session 1000 "a")
                      (%ev :pipeline :cron 1001 "b")))
         (s2 (%stream (%ev :adapter :session 1000 "a")
                      (%ev :pipeline :cron 1001 "b")))
         (report (run-parity-assertion *tui-parity-profile* s1 s2 1234)))
    (is eq :pass (par-overall-verdict report))
    (true (parity-report-pass-p report))
    (is = 0 (par-fail-count report))
    (is = 2 (par-pass-count report))))

(define-test (parity-assertion run-missing-fail-under-strict)
  (let* ((s1 (%stream (%ev :adapter :session 1000 "a")
                      (%ev :pipeline :cron 1001 "b")))
         (s2 (%stream (%ev :adapter :session 1000 "a")))
         (report (run-parity-assertion *tui-parity-profile* s1 s2 1235)))
    (is eq :fail (par-overall-verdict report))
    (false (parity-report-pass-p report))))

(define-test (parity-assertion run-missing-pass-under-relaxed)
  ;; Use a custom profile where :cron is NOT required, so delta=1 → :skip
  (let* ((relaxed-profile
           (make-assertion-profile
            :name "test-relaxed"
            :target :web
            :tolerance (make-tolerance-spec
                        :max-mismatches 0
                        :max-missing 1
                        :required-kinds '(:session))
            :required-sources '(:adapter :pipeline :store :harness)))
         (s1 (%stream (%ev :adapter :session 1000 "a")
                      (%ev :pipeline :cron 1001 "b")))
         (s2 (%stream (%ev :adapter :session 1000 "a")))
         (report (run-parity-assertion relaxed-profile s1 s2 1236)))
    (is eq :pass (par-overall-verdict report))
    (true (parity-report-pass-p report))
    (is = 0 (tdr-mismatched-count (par-diff-summary report)))))

(define-test (parity-assertion json-report)
  (let* ((s1 (%stream (%ev :adapter :session 1000 "a")))
         (s2 (%stream (%ev :adapter :session 1000 "a")))
         (report (run-parity-assertion *tui-parity-profile* s1 s2 1237))
         (json (parity-assertion-report->json report)))
    (true (search "report_id" json))
    (true (search "tui-strict" json))
    (true (search "\"verdict\":\"PASS\"" json))))

(define-test (parity-assertion empty-streams-pass)
  (let* ((s1 (%stream))
         (s2 (%stream))
         (report (run-parity-assertion *mcclim-parity-profile* s1 s2 1240)))
    (is eq :pass (par-overall-verdict report))
    (is = 0 (par-pass-count report))
    (is = 0 (par-fail-count report))))
