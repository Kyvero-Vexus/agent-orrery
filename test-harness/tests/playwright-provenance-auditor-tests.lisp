;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-provenance-auditor-tests.lisp — Tests for S1-S6 provenance auditor
;;; Bead: agent-orrery-kz5

(in-package #:orrery/harness-tests)

(define-test playwright-provenance-auditor-suite)

(defun %mk-prov-dir (prefix)
  (let ((d (format nil "/tmp/orrery-prov-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %cleanup-prov (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

;; Empty dir => all missing => pass=false, alarm-count=6
(define-test (playwright-provenance-auditor-suite empty-dir-all-alarms)
  (let* ((d (%mk-prov-dir "empty"))
         (a (orrery/adapter:run-playwright-provenance-audit
             d orrery/adapter:*playwright-canonical-command*)))
    (unwind-protect
         (progn
           (false (orrery/adapter:ppa-pass-p a))
           (is = 6 (orrery/adapter:ppa-alarm-count a)))
      (%cleanup-prov d))))

;; JSON fields
(define-test (playwright-provenance-auditor-suite json-fields)
  (let* ((d (%mk-prov-dir "json"))
         (a (orrery/adapter:run-playwright-provenance-audit
             d orrery/adapter:*playwright-canonical-command*))
         (json (orrery/adapter:playwright-provenance-audit->json a)))
    (unwind-protect
         (progn
           (true (search "\"pass\":" json))
           (true (search "\"alarm_count\":" json))
           (true (search "\"command_hash\":" json))
           (true (search "\"records\":" json))
           (true (search "\"lineage_ok\":" json)))
      (%cleanup-prov d))))

;; Alarm codes contain scenario ID
(define-test (playwright-provenance-auditor-suite alarm-codes-contain-scenario)
  (let* ((d (%mk-prov-dir "alarm"))
         (a (orrery/adapter:run-playwright-provenance-audit
             d orrery/adapter:*playwright-canonical-command*))
         (rec (first (orrery/adapter:ppa-records a))))
    (unwind-protect
         (true (find-if (lambda (c) (search "E4_PROV" c))
                        (orrery/adapter:ppr2-alarm-codes rec)))
      (%cleanup-prov d))))

;; Command hash matches canonical
(define-test (playwright-provenance-auditor-suite canonical-command-hash)
  (let* ((d (%mk-prov-dir "hash"))
         (a (orrery/adapter:run-playwright-provenance-audit
             d orrery/adapter:*playwright-canonical-command*)))
    (unwind-protect
         (is = orrery/adapter:*playwright-canonical-command-hash*
             (orrery/adapter:ppa-command-hash a))
      (%cleanup-prov d))))

;; Wrong command => cmd drift alarms
(define-test (playwright-provenance-auditor-suite wrong-command-drift)
  (let* ((d (%mk-prov-dir "drift"))
         (a (orrery/adapter:run-playwright-provenance-audit d "wrong-cmd")))
    (unwind-protect
         (let ((rec (first (orrery/adapter:ppa-records a))))
           (true (find-if (lambda (c) (search "CMD_DRIFT" c))
                          (orrery/adapter:ppr2-alarm-codes rec))))
      (%cleanup-prov d))))
