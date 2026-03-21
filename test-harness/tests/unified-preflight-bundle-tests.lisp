;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; unified-preflight-bundle-tests.lisp — tests for unified preflight bundle
;;; Bead: agent-orrery-pk7y

(in-package #:orrery/harness-tests)

(define-test unified-preflight-bundle-suite)

(defun %upb-mk-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-upb-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %upb-touch (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun %upb-clean (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun %upb-read-file (path)
  (with-open-file (s path :direction :input)
    (let ((buf (make-string (file-length s))))
      (read-sequence buf s)
      buf)))

(defun %upb-seed-web (dir ids)
  (%upb-touch (merge-pathnames "e2e-report.json" dir) "report")
  (dolist (sid ids)
    (%upb-touch (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%upb-touch (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip")))

(defun %upb-seed-tui (dir ids)
  (%upb-touch (merge-pathnames "tui-e2e-report.json" dir) "report")
  (%upb-touch (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid ids)
    (%upb-touch (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (%upb-touch (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (%upb-touch (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (%upb-touch (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(define-test (unified-preflight-bundle-suite full-pass-and-stable-key-order)
  (let ((web (%upb-mk-dir "web-ok"))
        (tui (%upb-mk-dir "tui-ok")))
    (unwind-protect
         (progn
           (%upb-seed-web web '("S1" "S2" "S3" "S4" "S5" "S6"))
           (%upb-seed-tui tui '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let* ((bundle (orrery/adapter:evaluate-unified-preflight-bundle
                           web "cd e2e && ./run-e2e.sh"
                           tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:unified-preflight-bundle->json bundle)))
             (true (orrery/adapter:upb-overall-pass-p bundle))
             (true (search "\"schema\":\"ep11-preflight-bundle-v1\"" json))
             (true (search "\"closure_gate\":" json))
             (true (search "\"protocol_matrix\":" json))
             (true (search "\"evidence_gaps\":" json))
             (true (< (search "\"closure_gate\":" json)
                      (search "\"protocol_matrix\":" json)
                      (search "\"evidence_gaps\":" json)))))
      (%upb-clean web)
      (%upb-clean tui))))

(define-test (unified-preflight-bundle-suite fail-closed-on-missing-playwright-s6)
  (let ((web (%upb-mk-dir "web-gap"))
        (tui (%upb-mk-dir "tui-ok2")))
    (unwind-protect
         (progn
           (%upb-seed-web web '("S1" "S2" "S3" "S4" "S5"))
           (%upb-seed-tui tui '("T1" "T2" "T3" "T4" "T5" "T6"))
           (let* ((bundle (orrery/adapter:evaluate-unified-preflight-bundle
                           web "cd e2e && ./run-e2e.sh"
                           tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (json (orrery/adapter:unified-preflight-bundle->json bundle)))
             (false (orrery/adapter:upb-overall-pass-p bundle))
             (true (search "epic4-playwright-s1-s6-evidence-missing" json))))
      (%upb-clean web)
      (%upb-clean tui))))

(define-test (unified-preflight-bundle-suite playwright-fixture-missing-trace-fails-closed)
  (let ((web (%upb-mk-dir "web-missing-trace"))
        (tui (%upb-mk-dir "tui-ok3")))
    (unwind-protect
         (progn
           (let* ((fixture (orrery/adapter:generate-playwright-fixture-set web :missing-trace))
                  (transcript (%upb-read-file (orrery/adapter:pfgr-command-transcript-path fixture))))
             (%upb-seed-tui tui '("T1" "T2" "T3" "T4" "T5" "T6"))
             (let* ((bundle (orrery/adapter:evaluate-unified-preflight-bundle
                             web (orrery/adapter:pfgr-deterministic-command fixture)
                             tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                    (json (orrery/adapter:unified-preflight-bundle->json bundle)))
               (false (orrery/adapter:upb-overall-pass-p bundle))
               (true (search "deterministic_command" transcript))
               (true (search "epic4-playwright-s1-s6-evidence-missing" json)))))
      (%upb-clean web)
      (%upb-clean tui))))

(define-test (unified-preflight-bundle-suite playwright-fixture-missing-scenario-fails-closed)
  (let ((web (%upb-mk-dir "web-missing-scenario"))
        (tui (%upb-mk-dir "tui-ok4")))
    (unwind-protect
         (progn
           (let ((fixture (orrery/adapter:generate-playwright-fixture-set web :missing-scenario)))
             (%upb-seed-tui tui '("T1" "T2" "T3" "T4" "T5" "T6"))
             (let* ((bundle (orrery/adapter:evaluate-unified-preflight-bundle
                             web (orrery/adapter:pfgr-deterministic-command fixture)
                             tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                    (json (orrery/adapter:unified-preflight-bundle->json bundle)))
               (false (orrery/adapter:upb-overall-pass-p bundle))
               (true (search "epic4-playwright-s1-s6-evidence-missing" json)))))
      (%upb-clean web)
      (%upb-clean tui))))
