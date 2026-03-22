;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; epic4-replay-cards-tests.lisp — tests for Epic 4 replay card emitter (cuvt)

(in-package #:orrery/tests)

(declaim (optimize (safety 3)))

(def-suite epic4-replay-cards
    :description "Tests for Epic 4 Playwright S1-S6 replay card emitter")

(in-suite epic4-replay-cards)

(test emit-epic4-replay-cards-returns-correct-count
  "Should emit exactly 6 replay cards for S1-S6 scenarios"
  (let ((cards (orrery/adapter:emit-epic4-replay-cards "/tmp/test-artifacts")))
    (is (= 6 (length cards)))
    (is (typep cards '(simple-array orrery/adapter:epic4-replay-card)))))

(test each-card-has-required-fields
  "Each replay card should have scenario ID, canonical command, and artifact paths"
  (let ((cards (orrery/adapter:emit-epic4-replay-cards "/tmp/test-artifacts")))
    (loop for card across cards
          do (progn
               (is (stringp (orrery/adapter:e4rc-scenario-id card)))
               (is (stringp (orrery/adapter:e4rc-canonical-command card)))
               (is (stringp (orrery/adapter:e4rc-screenshot-path card)))
               (is (stringp (orrery/adapter:e4rc-trace-path card)))
               (is (booleanp (orrery/adapter:e4rc-present-p card)))))))

(test cards-cover-all-s1-s6-scenarios
  "Cards should cover all S1-S6 scenarios in order"
  (let ((cards (orrery/adapter:emit-epic4-replay-cards "/tmp/test-artifacts"))
        (expected-scenarios '("S1" "S2" "S3" "S4" "S5" "S6")))
    (loop for expected-id in expected-scenarios
          for i from 0
          do (is (string= expected-id
                          (orrery/adapter:e4rc-scenario-id (aref cards i)))))))

(test canonical-command-is-deterministic
  "All cards should use the same deterministic Playwright command"
  (let ((cards (orrery/adapter:emit-epic4-replay-cards "/tmp/test-artifacts")))
    (loop for card across cards
          do (is (string= "cd e2e && ./run-e2e.sh"
                          (orrery/adapter:e4rc-canonical-command card))))))

(test screenshot-path-format
  "Screenshot paths should follow the expected format"
  (let ((cards (orrery/adapter:emit-epic4-replay-cards "/tmp/test-artifacts")))
    (loop for card across cards
          for scenario-id = (orrery/adapter:e4rc-scenario-id card)
          do (is (cl-ppcre:scan (format nil "artifacts/playwright/~A/screenshot\\.png" scenario-id)
                               (orrery/adapter:e4rc-screenshot-path card))))))

(test trace-path-format
  "Trace paths should follow the expected format"
  (let ((cards (orrery/adapter:emit-epic4-replay-cards "/tmp/test-artifacts")))
    (loop for card across cards
          for scenario-id = (orrery/adapter:e4rc-scenario-id card)
          do (is (cl-ppcre:scan (format nil "artifacts/playwright/~A/trace\\.zip" scenario-id)
                               (orrery/adapter:e4rc-trace-path card))))))

(test card-json-serialization
  "Cards should serialize to valid JSON with all fields"
  (let* ((cards (orrery/adapter:emit-epic4-replay-cards "/tmp/test-artifacts"))
         (card (aref cards 0))
         (json (orrery/adapter:epic4-replay-card->json card)))
    (is (stringp json))
    (is (cl-ppcre:scan "\"scenario_id\":" json))
    (is (cl-ppcre:scan "\"canonical_command\":" json))
    (is (cl-ppcre:scan "\"screenshot_path\":" json))
    (is (cl-ppcre:scan "\"trace_path\":" json))
    (is (cl-ppcre:scan "\"present\":" json))))

(test cards-array-json-serialization
  "Card arrays should serialize to valid JSON array"
  (let* ((cards (orrery/adapter:emit-epic4-replay-cards "/tmp/test-artifacts"))
         (json (orrery/adapter:epic4-replay-cards->json cards)))
    (is (stringp json))
    (is (char= #\[ (char json 0)))
    (is (char= #\] (char json (1- (length json)))))))

(test make-epic4-replay-card-for-single-scenario
  "Should create a valid replay card for a single scenario"
  (let ((card (orrery/adapter:make-epic4-replay-card-for-scenario "S3")))
    (is (string= "S3" (orrery/adapter:e4rc-scenario-id card)))
    (is (string= "cd e2e && ./run-e2e.sh"
                 (orrery/adapter:e4rc-canonical-command card)))
    (is (string= "artifacts/playwright/S3/screenshot.png"
                 (orrery/adapter:e4rc-screenshot-path card)))
    (is (string= "artifacts/playwright/S3/trace.zip"
                 (orrery/adapter:e4rc-trace-path card)))))
