;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; e2e-s1-runtime-matrix.lisp — Typed S1 runtime matrix + env contract gate

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

(defun truthy-env-p (name)
  (let ((v (env name)))
    (and (non-empty-string-p v)
         (member (string-downcase v) '("1" "true" "yes" "on") :test #'string=))))

(defun run-fixture-s1 ()
  (let* ((adapter (orrery/harness:make-fixture-adapter :clock (orrery/harness:make-fixture-clock)))
         (health (orrery/adapter:adapter-system-health adapter))
         (sessions (orrery/adapter:adapter-list-sessions adapter)))
    (and (plusp (length health))
         (plusp (length sessions))
         (every #'orrery/domain:health-record-p health)
         (every #'orrery/domain:session-record-p sessions))))

(defun validate-env-contract ()
  (let ((base (env "ORRERY_OPENCLAW_BASE_URL"))
        (require-live (truthy-env-p "ORRERY_REQUIRE_LIVE_PROFILE")))
    (cond
      ((and require-live (not (non-empty-string-p base)))
       (values nil "ORRERY_REQUIRE_LIVE_PROFILE=1 but ORRERY_OPENCLAW_BASE_URL is unset"))
      (t (values t "ok")))))

(defun main ()
  (format t "~&══ Agent Orrery S1 Runtime Matrix Gate ══~%")
  (multiple-value-bind (env-ok env-msg)
      (validate-env-contract)
    (format t "Env contract: ~A (~A)~%" (if env-ok "PASS" "FAIL") env-msg)
    (unless env-ok
      (sb-ext:exit :code 1)))

  (let ((fixture-ok (run-fixture-s1))
        (base (env "ORRERY_OPENCLAW_BASE_URL"))
        (live-ok nil)
        (live-required (truthy-env-p "ORRERY_REQUIRE_LIVE_PROFILE")))
    (format t "Fixture profile: ~A~%" (if fixture-ok "PASS" "FAIL"))

    (if (not (non-empty-string-p base))
        (format t "Live profile: SKIPPED (ORRERY_OPENCLAW_BASE_URL unset)~%")
        (let* ((token (env "ORRERY_OPENCLAW_TOKEN"))
               (report (orrery/adapter/openclaw:openclaw-live-contract-probe
                        :base-url base
                        :api-token (and (non-empty-string-p token) token)
                        :timeout-s 5)))
          (setf live-ok (orrery/adapter/openclaw:probe-report-overall-ok-p report))
          (format t "Live profile: ~A (~A)~%"
                  (if live-ok "PASS" "FAIL")
                  base)
          (dolist (r (orrery/adapter/openclaw:probe-report-results report))
            (format t "  - ~A: ~A~%"
                    (orrery/adapter/openclaw:probe-endpoint-result-endpoint r)
                    (if (orrery/adapter/openclaw:probe-endpoint-result-ok-p r) "ok" "mismatch")))))

    (let ((overall (and fixture-ok (or (not live-required) live-ok))))
      (format t "Overall gate: ~A~%" (if overall "PASS" "FAIL"))
      (sb-ext:exit :code (if overall 0 1)))))

(handler-case
    (main)
  (error (e)
    (format *error-output* "RUNTIME ERROR: ~A~%" e)
    (sb-ext:exit :code 2)))
