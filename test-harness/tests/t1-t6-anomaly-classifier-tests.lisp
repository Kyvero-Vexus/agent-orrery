;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; t1-t6-anomaly-classifier-tests.lisp
;;;   Tests for Epic 3 T1-T6 evidence anomaly classifier + remediation hint emitter.
;;;
;;; Bead: agent-orrery-8lum

(in-package #:orrery/harness-tests)

(define-test t1-t6-anomaly-classifier-suite)

;;; ── helpers ──────────────────────────────────────────────────────────────────

(defun %full-checksum-map-8lum ()
  (list (cons "transcript" "aaa") (cons "screenshot" "bbb")
        (cons "asciicast" "ccc") (cons "report" "ddd")))

(defun %make-clean-registry ()
  (orrery/adapter:build-registry-from-entries
   (mapcar (lambda (sid)
             (orrery/adapter:make-checksum-entry
              sid (%full-checksum-map-8lum) "digest-x"))
           '(:T1 :T2 :T3 :T4 :T5 :T6))))

;;; ── clean registry → :clean gate ────────────────────────────────────────────

(define-test (t1-t6-anomaly-classifier-suite clean-registry-yields-clean-gate)
  (let* ((reg (orrery/adapter:build-registry-from-entries
               (mapcar (lambda (sid)
                         (orrery/adapter:make-checksum-entry
                          sid (%full-checksum-map-8lum) "digest-ok"))
                       '(:T1 :T2 :T3 :T4 :T5 :T6))))
         (report (orrery/adapter:classify-registry-anomalies reg)))
    (is eq :clean (orrery/adapter:evaluate-anomaly-gate report)
        "full passing registry yields :clean gate")
    (is = 0 (orrery/adapter:anomrep-anomaly-count report)
        "zero anomalies for clean registry")))

;;; ── missing scenario → :rejected gate ───────────────────────────────────────

(define-test (t1-t6-anomaly-classifier-suite missing-scenario-rejected)
  (let* ((reg (orrery/adapter:build-registry-from-entries
               (list (orrery/adapter:make-checksum-entry
                      :T1 (%full-checksum-map-8lum) "d"))))
         (report (orrery/adapter:classify-registry-anomalies reg)))
    (is eq :rejected (orrery/adapter:evaluate-anomaly-gate report)
        "incomplete registry → :rejected (fail closed)")
    (let ((missing-anoms
           (remove :missing-scenario (orrery/adapter:anomrep-anomalies report)
                   :test-not #'eq
                   :key #'orrery/adapter:anom-anomaly-class)))
      (is = 5 (length missing-anoms)
          "5 :missing-scenario anomalies for T2-T6"))))

;;; ── artifact-missing anomaly ─────────────────────────────────────────────────

(define-test (t1-t6-anomaly-classifier-suite artifact-missing-anomaly)
  (let* ((partial-map (list (cons "transcript" "aaa") (cons "screenshot" "bbb")))
         (entries (cons (orrery/adapter:make-checksum-entry :T1 partial-map "d1")
                        (mapcar (lambda (sid)
                                  (orrery/adapter:make-checksum-entry
                                   sid (%full-checksum-map-8lum) "d"))
                                '(:T2 :T3 :T4 :T5 :T6))))
         (reg (orrery/adapter:build-registry-from-entries entries))
         (report (orrery/adapter:classify-registry-anomalies reg)))
    (is eq :anomalous (orrery/adapter:evaluate-anomaly-gate report)
        "missing artifact yields :anomalous (not :rejected) when all scenarios present")
    (let ((artifact-anoms
           (remove :artifact-missing (orrery/adapter:anomrep-anomalies report)
                   :test-not #'eq
                   :key #'orrery/adapter:anom-anomaly-class)))
      (true (>= (length artifact-anoms) 2)
            "at least 2 :artifact-missing anomalies for asciicast and report"))))

;;; ── rerun cross-comparison ───────────────────────────────────────────────────

(define-test (t1-t6-anomaly-classifier-suite rerun-clean-when-digests-match)
  (let* ((old-reg (%make-clean-registry))
         (new-reg (%make-clean-registry))
         (report (orrery/adapter:classify-rerun-anomalies old-reg new-reg)))
    (is eq :clean (orrery/adapter:evaluate-anomaly-gate report)
        "identical rerun registries → :clean")))

(define-test (t1-t6-anomaly-classifier-suite rerun-detects-digest-mismatch)
  (let* ((old-reg (%make-clean-registry))
         (new-entries (mapcar (lambda (sid)
                                (orrery/adapter:make-checksum-entry
                                 sid (%full-checksum-map-8lum)
                                 (if (eq sid :T1) "DIFFERENT-DIGEST" "digest-x")))
                              '(:T1 :T2 :T3 :T4 :T5 :T6)))
         (new-reg (orrery/adapter:build-registry-from-entries new-entries))
         (report (orrery/adapter:classify-rerun-anomalies old-reg new-reg)))
    (is eq :anomalous (orrery/adapter:evaluate-anomaly-gate report)
        "T1 digest change → :anomalous")
    (let ((mismatch-anoms
           (remove :transcript-digest-mismatch (orrery/adapter:anomrep-anomalies report)
                   :test-not #'eq
                   :key #'orrery/adapter:anom-anomaly-class)))
      (is = 1 (length mismatch-anoms)
          "one :transcript-digest-mismatch anomaly for T1"))))

(define-test (t1-t6-anomaly-classifier-suite rerun-missing-fails-closed)
  (let* ((old-reg (%make-clean-registry))
         (new-reg (orrery/adapter:build-registry-from-entries
                   (list (orrery/adapter:make-checksum-entry
                          :T1 (%full-checksum-map-8lum) "digest-x"))))
         (report (orrery/adapter:classify-rerun-anomalies old-reg new-reg)))
    (is eq :rejected (orrery/adapter:evaluate-anomaly-gate report)
        "missing scenarios in new run → :rejected (fail closed)")))

;;; ── JSON serialization ───────────────────────────────────────────────────────

(define-test (t1-t6-anomaly-classifier-suite anomaly-report-json-clean)
  (let* ((reg (%make-clean-registry))
         (report (orrery/adapter:classify-registry-anomalies reg))
         (json (orrery/adapter:anomaly-report->json report)))
    (true (search "\"gate_verdict\":\"CLEAN\"" json)
          "JSON gate_verdict is CLEAN")
    (true (search "\"anomaly_count\":0" json)
          "JSON anomaly_count is 0")))

(define-test (t1-t6-anomaly-classifier-suite anomaly-report-json-rejected)
  (let* ((reg (orrery/adapter:build-registry-from-entries nil))
         (report (orrery/adapter:classify-registry-anomalies reg))
         (json (orrery/adapter:anomaly-report->json report)))
    (true (search "\"gate_verdict\":\"REJECTED\"" json)
          "JSON gate_verdict is REJECTED for empty registry")))
