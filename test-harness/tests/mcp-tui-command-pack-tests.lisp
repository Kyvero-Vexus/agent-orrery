;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-

(in-package #:orrery/harness-tests)

(define-test mcp-tui-command-pack-suite)

(define-test (mcp-tui-command-pack-suite build-pack)
  (let ((pack (orrery/adapter:build-mcp-tui-command-pack)))
    (true (orrery/adapter:mtcp-pass-p pack))
    (is = 6 (length (orrery/adapter:mtcp-rows pack)))
    (is string=
        "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
        (orrery/adapter:mtcp-deterministic-command pack))))

(define-test (mcp-tui-command-pack-suite json-contains-t1)
  (let ((json (orrery/adapter:mcp-tui-command-pack->json
               (orrery/adapter:build-mcp-tui-command-pack))))
    (true (search "\"T1\"" json))
    (true (search "\"deterministic_command\"" json))))
