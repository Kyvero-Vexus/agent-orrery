;;; ci/check-tui-replay-drift-auditor.lisp — CI gate for tui-replay-drift-auditor (9vaf)
(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")
(asdf:load-system :agent-orrery)
(use-package :orrery/adapter)

(defun run-checks ()
  ;; Build a synthetic fingerprint batch with canonical command hash
  (let* ((cmd  *mcp-tui-deterministic-command*)
         (hash (command-fingerprint cmd))
         (scenarios '("T1" "T2" "T3" "T4" "T5" "T6"))
         (fps (mapcar (lambda (sid)
                        (make-tui-transcript-fingerprint
                         :scenario-id sid
                         :fingerprint 42
                         :command-hash hash))
                      scenarios))
         (batch (make-tui-fingerprint-batch
                 :fingerprints fps
                 :command-hash hash)))
    ;; First-run (no baseline) should pass
    (let ((verdict (audit-tui-replay-drift batch nil)))
      (assert (trdv-pass-p verdict) nil "FAIL: first-run should pass"))
    ;; Same batch as baseline → no drift
    (let ((verdict (audit-tui-replay-drift batch batch)))
      (assert (trdv-pass-p verdict) nil "FAIL: identical batch should pass"))
    ;; Introduce drift by changing one fingerprint
    (let* ((drifted-fps (mapcar (lambda (sid)
                                  (make-tui-transcript-fingerprint
                                   :scenario-id sid
                                   :fingerprint (if (string= sid "T3") 99 42)
                                   :command-hash hash))
                                scenarios))
           (drifted-batch (make-tui-fingerprint-batch
                           :fingerprints drifted-fps
                           :command-hash hash
                           ))
           (verdict (audit-tui-replay-drift drifted-batch batch)))
      (assert (not (trdv-pass-p verdict)) nil "FAIL: drifted batch should fail")
      (assert (= (trdv-drift-count verdict) 1) nil "FAIL: expected drift-count=1"))
    ;; JSON serializes without error
    (let* ((verdict (audit-tui-replay-drift batch nil))
           (j (tui-replay-drift-verdict->json verdict)))
      (assert (search "\"pass\":true" j) nil "FAIL: JSON missing pass:true"))
    (format t "~&[9vaf] tui-replay-drift-auditor: all checks PASSED~%")))

(run-checks)
(sb-ext:exit)
