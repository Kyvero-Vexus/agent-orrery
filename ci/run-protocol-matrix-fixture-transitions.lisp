;;; run-protocol-matrix-fixture-transitions.lisp
;;; Deterministic fixture runner for protocol/evidence matrix pass/fail transitions.

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)

(defun mk-temp-dir (prefix)
  (let ((dir (format nil "/tmp/orrery-protocol-matrix-~A-~D/" prefix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "seed" dir))
    dir))

(defun touch-file (path content)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (write-string content s)))

(defun seed-web (dir ids)
  (touch-file (merge-pathnames "e2e-report.json" dir) "report")
  (dolist (sid ids)
    (touch-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (touch-file (merge-pathnames (format nil "~A-trace.zip" sid) dir) "zip")))

(defun seed-tui (dir ids)
  (touch-file (merge-pathnames "tui-e2e-report.json" dir) "report")
  (touch-file (merge-pathnames "tui-e2e-session.cast" dir) "cast")
  (dolist (sid ids)
    (touch-file (merge-pathnames (format nil "~A-shot.png" sid) dir) "png")
    (touch-file (merge-pathnames (format nil "~A-transcript.txt" sid) dir) "txt")
    (touch-file (merge-pathnames (format nil "~A-asciicast.cast" sid) dir) "cast")
    (touch-file (merge-pathnames (format nil "~A-report.json" sid) dir) "report")))

(defun cleanup-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(defun run-case (label web-ids tui-ids)
  (let ((web (mk-temp-dir (format nil "~A-web" label)))
        (tui (mk-temp-dir (format nil "~A-tui" label))))
    (unwind-protect
         (progn
           (seed-web web web-ids)
           (seed-tui tui tui-ids)
           (let* ((res (orrery/adapter:evaluate-protocol-evidence-matrix
                        web "cd e2e && ./run-e2e.sh"
                        tui "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
                  (ok (orrery/adapter:pmrep-overall-pass-p res))
                  (json (orrery/adapter:protocol-matrix-report->json res)))
             (format t "~A => ~A~%~A~%" label (if ok "PASS" "FAIL") json)
             ok))
      (cleanup-dir web)
      (cleanup-dir tui))))

(let* ((pass-ok (run-case "case-pass-both-complete"
                          '("S1" "S2" "S3" "S4" "S5" "S6")
                          '("T1" "T2" "T3" "T4" "T5" "T6")))
       (fail-epic4-ok (not (run-case "case-fail-epic4-missing-s6"
                                     '("S1" "S2" "S3" "S4" "S5")
                                     '("T1" "T2" "T3" "T4" "T5" "T6"))))
       (fail-epic3-ok (not (run-case "case-fail-epic3-missing-t6"
                                     '("S1" "S2" "S3" "S4" "S5" "S6")
                                     '("T1" "T2" "T3" "T4" "T5")))))
  (unless (and pass-ok fail-epic4-ok fail-epic3-ok)
    (error "Protocol-matrix transition fixture run failed")))

(uiop:quit 0)
