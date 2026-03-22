(in-package #:orrery/harness-tests)

(define-test playwright-scenario-ledger-suite)

(defun %mk-web-ledger-dir (prefix)
  (let ((d (format nil "/tmp/orrery-web-ledger-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" d))
    d))

(defun %touch-web-ledger (p c)
  (with-open-file (s p :direction :output :if-exists :supersede)
    (write-string c s)))

(defun %cleanup-web-ledger (d)
  (when (probe-file d)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild) (pathname d))))
      (ignore-errors (delete-file f)))))

(define-test (playwright-scenario-ledger-suite write-ledger-json)
  (let ((d (%mk-web-ledger-dir "ok")))
    (unwind-protect
         (progn
           (%touch-web-ledger (merge-pathnames "playwright-report.json" d) "S1 S2 S3 S4 S5 S6")
           (%touch-web-ledger (merge-pathnames "ok.png" d) "png")
           (%touch-web-ledger (merge-pathnames "ok.zip" d) "zip")
           (let ((l (orrery/adapter:write-playwright-scenario-ledger d "cd e2e && ./run-e2e.sh")))
             (true l)
             (true (probe-file (merge-pathnames "playwright-scenario-ledger.json" d)))
             (let ((json (orrery/adapter:playwright-scenario-ledger->json l)))
               (true (search "attestation_count" json))
               (true (search "\"command_hash\":" json))
               (true (search "\"scenarios\":" json))
               (true (search "\"missing_attestations\":" json)))))
      (%cleanup-web-ledger d))))
