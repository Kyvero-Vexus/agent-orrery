;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-reproducibility-reporter-tests.lisp
;;;   Tests for the S1-S6 reproducibility reporter.
;;;   Bead: agent-orrery-bxf5

(in-package #:orrery/harness-tests)

(define-test playwright-reproducibility-reporter-suite)

;;; ─── Helpers ─────────────────────────────────────────────────────────────────

(defun %mk-repro-dir (prefix)
  (let ((d (format nil "/tmp/orrery-repro-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %cleanup-repro (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

(defun %write-text-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

;;; ─── Unit tests for build-s1-s6-rerun-sample ─────────────────────────────────

;; Missing artifacts → stable-p nil, digests empty
(define-test (playwright-reproducibility-reporter-suite build-sample-missing-artifacts)
  (let* ((d (%mk-repro-dir "miss"))
         (s (orrery/adapter:build-s1-s6-rerun-sample
             "S1" 0 d "s1.png" "s1.trace")))
    (unwind-protect
         (progn
           (is string= "S1" (orrery/adapter:rrs-scenario-id s))
           (is = 0 (orrery/adapter:rrs-rerun-index s))
           (false (orrery/adapter:rrs-artifact-stable-p s))
           (is string= "" (orrery/adapter:rrs-screenshot-digest s))
           (is string= "" (orrery/adapter:rrs-trace-digest s)))
      (%cleanup-repro d))))

;; Present artifacts → stable-p t, digests non-empty
(define-test (playwright-reproducibility-reporter-suite build-sample-present-artifacts)
  (let* ((d (%mk-repro-dir "pres")))
    (unwind-protect
         (progn
           (%write-text-file (merge-pathnames "s2.png" d) "FAKE-PNG-BYTES")
           (%write-text-file (merge-pathnames "s2.trace" d) "FAKE-TRACE")
           (let ((s (orrery/adapter:build-s1-s6-rerun-sample
                     "S2" 1 d "s2.png" "s2.trace")))
             (true (orrery/adapter:rrs-artifact-stable-p s))
             (false (string= "" (orrery/adapter:rrs-screenshot-digest s)))
             (false (string= "" (orrery/adapter:rrs-trace-digest s)))))
      (%cleanup-repro d))))

;;; ─── Unit tests for compute-scenario-reproducibility-score ──────────────────

;; 0 samples → ratio=0.0 pass=nil
(define-test (playwright-reproducibility-reporter-suite score-zero-samples)
  (let* ((canonical (orrery/adapter:command-fingerprint
                     orrery/adapter:*playwright-canonical-command*))
         (score (orrery/adapter:compute-scenario-reproducibility-score
                 "S1" '() canonical)))
    (false (orrery/adapter:srs-pass-p score))
    (is = 0 (orrery/adapter:srs-sample-count score))
    (is = 0 (orrery/adapter:srs-stable-count score))
    (is = 0.0 (orrery/adapter:srs-stability-ratio score))))

;; All stable, no fp drift → pass=t, ratio=1.0, delta=0
(define-test (playwright-reproducibility-reporter-suite score-all-stable)
  (let* ((canonical (orrery/adapter:command-fingerprint
                     orrery/adapter:*playwright-canonical-command*))
         (samples (loop for i from 0 below 3
                        collect (orrery/adapter:make-s1-s6-rerun-sample
                                 :scenario-id "S3"
                                 :rerun-index i
                                 :screenshot-digest (format nil "SCR~D" i)
                                 :trace-digest (format nil "TRC~D" i)
                                 :command-hash canonical
                                 :artifact-stable-p t)))
         (score (orrery/adapter:compute-scenario-reproducibility-score
                 "S3" samples canonical)))
    (true (orrery/adapter:srs-pass-p score))
    (is = 3 (orrery/adapter:srs-sample-count score))
    (is = 3 (orrery/adapter:srs-stable-count score))
    (is = 1.0 (orrery/adapter:srs-stability-ratio score))
    (is = 0 (orrery/adapter:srs-command-fingerprint-delta score))
    (false (null (orrery/adapter:srs-artifact-hash-chain score)))))

;; One unstable sample → pass=nil, alarm present
(define-test (playwright-reproducibility-reporter-suite score-one-unstable)
  (let* ((canonical (orrery/adapter:command-fingerprint
                     orrery/adapter:*playwright-canonical-command*))
         (good (orrery/adapter:make-s1-s6-rerun-sample
                :scenario-id "S4" :rerun-index 0 :screenshot-digest "A"
                :trace-digest "B" :command-hash canonical :artifact-stable-p t))
         (bad  (orrery/adapter:make-s1-s6-rerun-sample
                :scenario-id "S4" :rerun-index 1 :screenshot-digest ""
                :trace-digest "" :command-hash canonical :artifact-stable-p nil))
         (score (orrery/adapter:compute-scenario-reproducibility-score
                 "S4" (list good bad) canonical)))
    (false (orrery/adapter:srs-pass-p score))
    (is = 1 (orrery/adapter:srs-stable-count score))
    (false (null (orrery/adapter:srs-alarm-codes score)))))

;; FP drift → alarm, pass=nil
(define-test (playwright-reproducibility-reporter-suite score-fp-drift)
  (let* ((canonical (orrery/adapter:command-fingerprint
                     orrery/adapter:*playwright-canonical-command*))
         (drifted  (orrery/adapter:make-s1-s6-rerun-sample
                    :scenario-id "S5" :rerun-index 0 :screenshot-digest "X"
                    :trace-digest "Y" :command-hash 9999999 :artifact-stable-p t))
         (score (orrery/adapter:compute-scenario-reproducibility-score
                 "S5" (list drifted) canonical)))
    (false (orrery/adapter:srs-pass-p score))
    (is = 1 (orrery/adapter:srs-command-fingerprint-delta score))
    (true (some (lambda (a) (search "CMD_FINGERPRINT_DELTA" a))
                (orrery/adapter:srs-alarm-codes score)))))

;;; ─── compile-playwright-reproducibility-report ───────────────────────────────

;; Empty alist → overall 0.0, not closure ready
(define-test (playwright-reproducibility-reporter-suite report-empty)
  (let* ((rpt (orrery/adapter:compile-playwright-reproducibility-report
               "run-empty" "/tmp" '())))
    (false (orrery/adapter:prr-closure-ready-p rpt))
    (is = 0.0 (orrery/adapter:prr-overall-stability-ratio rpt))
    (true (null (orrery/adapter:prr-scenarios rpt)))))

;; All scenarios pass → closure-ready-p t
(define-test (playwright-reproducibility-reporter-suite report-all-pass)
  (let* ((canonical (orrery/adapter:command-fingerprint
                     orrery/adapter:*playwright-canonical-command*))
         (make-samples
           (lambda (sid)
             (loop for i from 0 below 2
                   collect (orrery/adapter:make-s1-s6-rerun-sample
                            :scenario-id sid :rerun-index i
                            :screenshot-digest (format nil "~A-SCR~D" sid i)
                            :trace-digest (format nil "~A-TRC~D" sid i)
                            :command-hash canonical :artifact-stable-p t))))
         (alist (mapcar (lambda (sid) (cons sid (funcall make-samples sid)))
                        '("S1" "S2" "S3" "S4" "S5" "S6")))
         (rpt (orrery/adapter:compile-playwright-reproducibility-report
               "run-all-pass" "/tmp" alist)))
    (true (orrery/adapter:prr-closure-ready-p rpt))
    (is = 1.0 (orrery/adapter:prr-overall-stability-ratio rpt))
    (true (orrery/adapter:prr-command-fingerprint-stable-p rpt))
    (true (orrery/adapter:prr-artifact-hash-chain-ok-p rpt))
    (true (null (orrery/adapter:prr-alarm-codes rpt)))))

;;; ─── JSON serialisation ──────────────────────────────────────────────────────

(define-test (playwright-reproducibility-reporter-suite json-fields)
  (let* ((rpt (orrery/adapter:compile-playwright-reproducibility-report
               "run-json" "/tmp" '()))
         (j   (orrery/adapter:playwright-reproducibility-report->json rpt)))
    (true (search "\"run_id\":" j))
    (true (search "\"overall_stability_ratio\":" j))
    (true (search "\"closure_ready\":" j))
    (true (search "\"command_fingerprint_stable\":" j))
    (true (search "\"artifact_hash_chain_ok\":" j))
    (true (search "\"alarm_codes\":" j))
    (true (search "\"timestamp\":" j))
    (true (search "\"detail\":" j))
    (true (search "\"scenarios\":" j))))

(define-test (playwright-reproducibility-reporter-suite json-round-trip-detail)
  (let* ((canonical (orrery/adapter:command-fingerprint
                     orrery/adapter:*playwright-canonical-command*))
         (sample (orrery/adapter:make-s1-s6-rerun-sample
                  :scenario-id "S1" :rerun-index 0 :screenshot-digest "SCR"
                  :trace-digest "TRC" :command-hash canonical :artifact-stable-p t))
         (alist `(("S1" . ,(list sample))))
         (rpt (orrery/adapter:compile-playwright-reproducibility-report
               "run-rt" "/tmp" alist))
         (j (orrery/adapter:playwright-reproducibility-report->json rpt)))
    (true (search "\"S1\"" j))
    (true (search "\"stability_ratio\":" j))))
