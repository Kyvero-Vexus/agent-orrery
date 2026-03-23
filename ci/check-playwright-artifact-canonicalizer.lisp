;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; check-playwright-artifact-canonicalizer.lisp — CI gate for S1-S6 artifact canonicalizer + preflight
;;; Bead: agent-orrery-bt9
;;;
;;; Usage:
;;;   WEB_EVIDENCE_DIR=<dir> WEB_EVIDENCE_COMMAND=<cmd> sbcl --script ci/check-playwright-artifact-canonicalizer.lisp
;;;
;;; Exits 0 on pass, 1 on fail.

(load "/home/slime/quicklisp/setup.lisp")
(ql:quickload :agent-orrery :silent t)

(let* ((root (or (uiop:getenv "WEB_EVIDENCE_DIR")
                 "test-results/e2e-regression-matrix/complete/"))
       (cmd  (or (uiop:getenv "WEB_EVIDENCE_COMMAND")
                 "cd e2e && ./run-e2e.sh"))
       (verdict (orrery/adapter:run-playwright-s1-s6-preflight root cmd))
       (json (orrery/adapter:playwright-preflight-verdict->json verdict)))
  (format t "~A~%" json)
  (unless (orrery/adapter:ppv-pass-p verdict)
    (uiop:quit 1)))
