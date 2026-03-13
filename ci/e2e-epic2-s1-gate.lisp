;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; e2e-epic2-s1-gate.lisp — Epic 2 E2E Gate: Scenario S1 (fixture + live)
;;;
;;; Verifies S1 (Health + Session Snapshot) on:
;;;   1) deterministic fixture adapter (mandatory)
;;;   2) live OpenClaw-compatible runtime (when ORRERY_OPENCLAW_BASE_URL is set)
;;;
;;; Exit codes:
;;;   0 — gate passed (fixture passed, live passed or explicitly skipped)
;;;   1 — gate failed
;;;   2 — load/runtime error

(require :asdf)

(handler-case
    (load "/home/slime/quicklisp/setup.lisp")
  (error () nil))

(dolist (path (list #P"/home/slime/projects/agent-orrery/"
                    (truename ".")))
  (pushnew path asdf:*central-registry* :test #'equal))
(asdf:clear-source-registry)

(handler-case
    (ql:quickload :agent-orrery/test-harness :silent t)
  (error (e)
    (format *error-output* "~&LOAD ERROR: ~A~%" e)
    (sb-ext:exit :code 2)))

(defun env (name)
  #+sbcl (sb-ext:posix-getenv name)
  #-sbcl (declare (ignore name))
  #-sbcl nil)

(defun non-empty-string-p (x)
  (and (stringp x) (> (length x) 0)))

(defun check-s1 (adapter label)
  (let ((checks 0)
        (passed 0)
        (failures '()))
    (flet ((check (description ok)
             (incf checks)
             (if ok
                 (progn
                   (incf passed)
                   (format t "  ✔ [~A] ~A~%" label description))
                 (progn
                   (push description failures)
                   (format t "  ✘ [~A] ~A~%" label description)))))
      (let ((health (orrery/adapter:adapter-system-health adapter)))
        (check "system-health returns non-empty list"
               (plusp (length health)))
        (check "all health entries are health-record"
               (every #'orrery/domain:health-record-p health))
        (check "health statuses are keyword symbols"
               (every #'keywordp (mapcar #'orrery/domain:hr-status health))))

      (let ((sessions (orrery/adapter:adapter-list-sessions adapter)))
        (check "list-sessions returns list"
               (listp sessions))
        (check "all session entries are session-record"
               (every #'orrery/domain:session-record-p sessions))
        (check "session ids are strings"
               (every (lambda (s) (stringp (orrery/domain:sr-id s))) sessions))
        (check "session model fields are strings"
               (every (lambda (s) (stringp (orrery/domain:sr-model s))) sessions))
        (check "session token counts are non-negative"
               (every (lambda (s) (>= (orrery/domain:sr-total-tokens s) 0)) sessions)))

      (values (= checks passed)
              checks
              passed
              (nreverse failures)))))

(defun run-fixture-s1 ()
  (format t "~&━━━ Scenario S1 (Fixture) ━━━~%")
  (let* ((clock (orrery/harness:make-fixture-clock))
         (adapter (orrery/harness:make-fixture-adapter :clock clock)))
    (check-s1 adapter "fixture")))

(defun run-live-s1 ()
  (let ((base (env "ORRERY_OPENCLAW_BASE_URL")))
    (if (not (non-empty-string-p base))
        (progn
          (format t "~&━━━ Scenario S1 (Live) ━━━~%")
          (format t "  ⓘ [live] skipped: ORRERY_OPENCLAW_BASE_URL not set~%")
          (values :skipped 0 0 '()))
        (progn
          (format t "~&━━━ Scenario S1 (Live) ━━━~%")
          (format t "  ⓘ [live] base-url: ~A~%" base)
          (let* ((token (env "ORRERY_OPENCLAW_TOKEN"))
                 (adapter (orrery/adapter/openclaw:make-openclaw-adapter
                           :base-url base
                           :api-token (and (non-empty-string-p token) token)
                           :timeout-s 10)))
            (handler-case
                (check-s1 adapter "live")
              (error (e)
                (format t "  ✘ [live] runtime error: ~A~%" e)
                (values nil 1 0 (list (princ-to-string e))))))))))

(defun main ()
  (format t "~&══════════════════════════════════════════════════════════~%")
  (format t "  Agent Orrery — Epic 2 E2E Gate (S1)~%")
  (format t "══════════════════════════════════════════════════════════~%")

  (multiple-value-bind (fixture-ok fixture-checks fixture-passed fixture-failures)
      (run-fixture-s1)
    (declare (ignore fixture-failures))
    (multiple-value-bind (live-ok live-checks live-passed live-failures)
        (run-live-s1)
      (format t "~&══════════════════════════════════════════════════════════~%")
      (format t "  SUMMARY~%")
      (format t "══════════════════════════════════════════════════════════~%~%")
      (format t "Fixture: ~:[FAILED~;PASSED~] (~D/~D checks)~%"
              fixture-ok fixture-passed fixture-checks)
      (cond
        ((eq live-ok :skipped)
         (format t "Live:    SKIPPED (endpoint not configured)~%"))
        (t
         (format t "Live:    ~:[FAILED~;PASSED~] (~D/~D checks)~%"
                 live-ok live-passed live-checks)))
      (when live-failures
        (format t "~&Live failures:~%")
        (dolist (f live-failures)
          (format t "  - ~A~%" f)))

      (if (and fixture-ok (or (eq live-ok :skipped) live-ok))
          (progn
            (format t "~&══ EPIC 2 S1 GATE: PASSED ══~%")
            (sb-ext:exit :code 0))
          (progn
            (format t "~&══ EPIC 2 S1 GATE: FAILED ══~%")
            (sb-ext:exit :code 1))))))

(handler-case
    (main)
  (error (e)
    (format *error-output* "~&RUNTIME ERROR: ~A~%" e)
    (sb-ext:exit :code 2)))
