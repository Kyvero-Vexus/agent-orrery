;;; Run TUI provider tests only
(asdf:clear-source-registry)
(asdf:initialize-source-registry)
(asdf:load-system "agent-orrery")
(ql:quickload "parachute")

;; Load test packages
(load (merge-pathnames "test-harness/packages.lisp" (asdf:system-source-directory "agent-orrery")))

;; Load just TUI provider tests
(load (merge-pathnames "test-harness/tests/tui-provider-tests.lisp" (asdf:system-source-directory "agent-orrery")))

;; Run
(parachute:test 'orrery/harness-tests::tui-provider-suite :report 'parachute:interactive)
