;;; Run TUI provider tests only
(asdf:clear-source-registry)
(asdf:initialize-source-registry)
(asdf:load-system "agent-orrery")
(ql:quickload "parachute")

;; Load test harness packages (defines orrery/harness-tests with :use parachute)
(let ((base (asdf:system-source-directory "agent-orrery")))
  (load (merge-pathnames "test-harness/packages.lisp" base))
  (load (merge-pathnames "test-harness/tests/tui-provider-tests.lisp" base)))

;; Run
(let ((results (parachute:test 'orrery/harness-tests::tui-provider-suite :report 'parachute:plain)))
  (format t "~%~%=== FINAL STATUS: ~A ===~%" (parachute:status results))
  (sb-ext:exit :code (if (eq :passed (parachute:status results)) 0 1)))
