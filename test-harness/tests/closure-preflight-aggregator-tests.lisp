;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; closure-preflight-aggregator-tests.lisp — Test skeleton for bv0
;;; Bead: agent-orrery-bv0

(in-package #:orrery/test-harness/tests)

(define-test "closure-preflight-aggregator: structure construction"
  :parent-suite 'adapter-tests
  (let* ((epic3-track (make-preflight-track-record
                        :framework :mcp-tui-driver
                        :pass-p t
                        :command-match-p t
                        :command-hash 12345
                        :required-scenarios 6
                        :complete-scenarios 6
                        :missing-scenarios nil
                        :detail "Epic 3 complete"
                        :timestamp (get-universal-time)))
         (epic4-track (make-preflight-track-record
                        :framework :playwright
                        :pass-p t
                        :command-match-p t
                        :command-hash 67890
                        :required-scenarios 6
                        :complete-scenarios 6
                        :missing-scenarios nil
                        :detail "Epic 4 complete"
                        :timestamp (get-universal-time)))
         (aggregate (aggregate-closure-preflight epic3-track epic4-track)))
    (true (closure-preflight-aggregate-p aggregate))
    (true (cpa-pass-p aggregate))
    (is eq :closed (cpa-verdict aggregate))
    (true (cpa-epic3-pass-p aggregate))
    (true (cpa-epic4-pass-p aggregate))
    (true (cpa-commands-match-p aggregate))
    (is = 12 (cpa-total-scenarios aggregate))
    (is = 12 (cpa-total-complete aggregate))
    (is = 0 (cpa-total-missing aggregate))
    (false (cpa-blocking-issues aggregate))))

(define-test "closure-preflight-aggregator: fail-closed on missing epic3"
  :parent-suite 'adapter-tests
  (let* ((epic3-track (make-preflight-track-record
                        :framework :mcp-tui-driver
                        :pass-p nil
                        :command-match-p t
                        :command-hash 12345
                        :required-scenarios 6
                        :complete-scenarios 4
                        :missing-scenarios '("T5" "T6")
                        :detail "Missing T5, T6"
                        :timestamp (get-universal-time)))
         (epic4-track (make-preflight-track-record
                        :framework :playwright
                        :pass-p t
                        :command-match-p t
                        :command-hash 67890
                        :required-scenarios 6
                        :complete-scenarios 6
                        :missing-scenarios nil
                        :detail "Epic 4 complete"
                        :timestamp (get-universal-time)))
         (aggregate (aggregate-closure-preflight epic3-track epic4-track)))
    (false (cpa-pass-p aggregate))
    (is eq :open (cpa-verdict aggregate))
    (false (cpa-epic3-pass-p aggregate))
    (true (cpa-epic4-pass-p aggregate))
    (false (null (cpa-blocking-issues aggregate)))))

(define-test "closure-preflight-aggregator: fail-closed on missing epic4"
  :parent-suite 'adapter-tests
  (let* ((epic3-track (make-preflight-track-record
                        :framework :mcp-tui-driver
                        :pass-p t
                        :command-match-p t
                        :command-hash 12345
                        :required-scenarios 6
                        :complete-scenarios 6
                        :missing-scenarios nil
                        :detail "Epic 3 complete"
                        :timestamp (get-universal-time)))
         (epic4-track (make-preflight-track-record
                        :framework :playwright
                        :pass-p nil
                        :command-match-p t
                        :command-hash 67890
                        :required-scenarios 6
                        :complete-scenarios 3
                        :missing-scenarios '("S4" "S5" "S6")
                        :detail "Missing S4, S5, S6"
                        :timestamp (get-universal-time)))
         (aggregate (aggregate-closure-preflight epic3-track epic4-track)))
    (false (cpa-pass-p aggregate))
    (is eq :open (cpa-verdict aggregate))
    (true (cpa-epic3-pass-p aggregate))
    (false (cpa-epic4-pass-p aggregate))
    (is = 3 (length (cpa-blocking-issues aggregate)))))

(define-test "closure-preflight-aggregator: fail-closed on command drift"
  :parent-suite 'adapter-tests
  (let* ((epic3-track (make-preflight-track-record
                        :framework :mcp-tui-driver
                        :pass-p t
                        :command-match-p nil
                        :command-hash 99999
                        :required-scenarios 6
                        :complete-scenarios 6
                        :missing-scenarios nil
                        :detail "Epic 3 command drift"
                        :timestamp (get-universal-time)))
         (epic4-track (make-preflight-track-record
                        :framework :playwright
                        :pass-p t
                        :command-match-p t
                        :command-hash 67890
                        :required-scenarios 6
                        :complete-scenarios 6
                        :missing-scenarios nil
                        :detail "Epic 4 complete"
                        :timestamp (get-universal-time)))
         (aggregate (aggregate-closure-preflight epic3-track epic4-track)))
    (false (cpa-pass-p aggregate))
    (is eq :open (cpa-verdict aggregate))
    (false (cpa-commands-match-p aggregate))))

(define-test "closure-preflight-aggregator: JSON serialization"
  :parent-suite 'adapter-tests
  (let* ((epic3-track (make-preflight-track-record
                        :framework :mcp-tui-driver
                        :pass-p t
                        :command-match-p t
                        :command-hash 12345
                        :required-scenarios 6
                        :complete-scenarios 6
                        :missing-scenarios nil
                        :detail "Epic 3 complete"
                        :timestamp 3920000000))
         (epic4-track (make-preflight-track-record
                        :framework :playwright
                        :pass-p t
                        :command-match-p t
                        :command-hash 67890
                        :required-scenarios 6
                        :complete-scenarios 6
                        :missing-scenarios nil
                        :detail "Epic 4 complete"
                        :timestamp 3920000000))
         (aggregate (aggregate-closure-preflight epic3-track epic4-track))
         (json (closure-preflight-aggregate->json aggregate)))
    (true (stringp json))
    (true (search "\"pass\":true" json))
    (true (search "\"verdict\":\"closed\"" json))
    (true (search "\"epic3_pass\":true" json))
    (true (search "\"epic4_pass\":true" json))
    (true (search "\"commands_match\":true" json))
    (true (search "\"total\":12" json))
    (true (search "\"complete\":12" json))
    (true (search "\"missing\":0" json))))

(define-test "closure-preflight-aggregator: track record JSON"
  :parent-suite 'adapter-tests
  (let* ((track (make-preflight-track-record
                  :framework :playwright
                  :pass-p nil
                  :command-match-p t
                  :command-hash 12345
                  :required-scenarios 6
                  :complete-scenarios 4
                  :missing-scenarios '("S5" "S6")
                  :detail "Missing scenarios"
                  :timestamp 3920000000))
         (json (track-record->json track)))
    (true (stringp json))
    (true (search "\"framework\":\"playwright\"" json))
    (true (search "\"pass\":false" json))
    (true (search "\"missing_count\":2" json))
    (true (search "\"S5\"" json))
    (true (search "\"S6\"" json))))

(define-test "closure-preflight-aggregator: blocking issues enumeration"
  :parent-suite 'adapter-tests
  (let* ((epic3-track (make-preflight-track-record
                        :framework :mcp-tui-driver
                        :pass-p nil
                        :command-match-p nil
                        :command-hash 99999
                        :required-scenarios 6
                        :complete-scenarios 4
                        :missing-scenarios '("T5" "T6")
                        :detail "Multiple issues"
                        :timestamp (get-universal-time)))
         (epic4-track (make-preflight-track-record
                        :framework :playwright
                        :pass-p nil
                        :command-match-p nil
                        :command-hash 88888
                        :required-scenarios 6
                        :complete-scenarios 3
                        :missing-scenarios '("S4" "S5" "S6")
                        :detail "Multiple issues"
                        :timestamp (get-universal-time)))
         (aggregate (aggregate-closure-preflight epic3-track epic4-track))
         (blocking (cpa-blocking-issues aggregate)))
    (true (listp blocking))
    (true (>= (length blocking) 4))  ; At least 4 distinct issues
    ;; Check blocking issues mention key problems
    (let ((blocking-str (format nil "~{~A~^ ~%" blocking)))
      (true (search "Epic 3" blocking-str))
      (true (search "Epic 4" blocking-str))
      (true (search "command" blocking-str)))))
