;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-pack-index.lisp — deterministic Playwright evidence pack index
;;; Bead: agent-orrery-nml0

(in-package #:orrery/adapter)

(defstruct (playwright-attest-row (:conc-name pear-))
  (scenario-id "" :type string)
  (screenshot-digest "" :type string)
  (trace-digest "" :type string)
  (complete-p nil :type boolean))

(defstruct (playwright-replay-card (:conc-name pprc-))
  (scenario-id "" :type string)
  (command "" :type string)
  (command-hash 0 :type integer)
  (replay-command "" :type string)
  (screenshot-digest "" :type string)
  (trace-digest "" :type string)
  (ready-p nil :type boolean))

(defstruct (playwright-evidence-pack-index (:conc-name pepi-))
  (pass-p nil :type boolean)
  (command-match-p nil :type boolean)
  (command-hash 0 :type integer)
  (scenario-count 0 :type integer)
  (artifact-count 0 :type integer)
  (missing-scenarios nil :type list)
  (attest-rows nil :type list)
  (replay-cards nil :type list)
  (command-table nil :type list)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string) (values boolean &optional)) canonical-playwright-command-p)
 (ftype (function (runner-evidence-manifest string evidence-artifact-kind) (values (or null evidence-artifact) &optional))
        find-scenario-artifact)
 (ftype (function (runner-evidence-manifest) (values list &optional)) build-playwright-attest-rows)
 (ftype (function (runner-evidence-manifest string) (values list &optional)) build-playwright-replay-cards)
 (ftype (function (string string) (values playwright-evidence-pack-index &optional))
        build-playwright-evidence-pack-index)
 (ftype (function (playwright-evidence-pack-index) (values string &optional))
        playwright-evidence-pack-index->json))

(defun canonical-playwright-command-p (command)
  (declare (type string command))
  (or (string= command *playwright-deterministic-command*)
      (string= command "bash run-e2e.sh")
      (string= command "cd e2e && bash run-e2e.sh")))

(defun find-scenario-artifact (manifest scenario-id kind)
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id)
           (type evidence-artifact-kind kind))
  (find-if (lambda (a)
             (and (string= scenario-id (ea-scenario-id a))
                  (eq kind (ea-artifact-kind a))
                  (ea-present-p a)))
           (rem-artifacts manifest)))

(defun %missing-s1-s6 (manifest)
  (declare (type runner-evidence-manifest manifest))
  (let ((missing nil))
    (dolist (sid *playwright-required-scenarios*)
      (let ((shot (find-scenario-artifact manifest sid :screenshot))
            (trace (find-scenario-artifact manifest sid :trace)))
        (unless (and shot trace)
          (push sid missing))))
    (nreverse missing)))

(defun build-playwright-attest-rows (manifest)
  (declare (type runner-evidence-manifest manifest)
           (optimize (safety 3)))
  (let ((rows nil))
    (dolist (sid *playwright-required-scenarios* (nreverse rows))
      (let* ((shot (find-scenario-artifact manifest sid :screenshot))
             (trace (find-scenario-artifact manifest sid :trace))
             (shot-digest (if shot (file-sha256 (ea-path shot)) ""))
             (trace-digest (if trace (file-sha256 (ea-path trace)) ""))
             (complete (and (not (null shot)) (not (null trace)))))
        (push (make-playwright-attest-row
               :scenario-id sid
               :screenshot-digest shot-digest
               :trace-digest trace-digest
               :complete-p complete)
              rows)))))

(defun build-playwright-replay-cards (manifest command)
  (declare (type runner-evidence-manifest manifest)
           (type string command)
           (optimize (safety 3)))
  (let ((cards nil)
        (deterministic *playwright-deterministic-command*))
    (dolist (sid *playwright-required-scenarios* (nreverse cards))
      (let* ((shot (find-scenario-artifact manifest sid :screenshot))
             (trace (find-scenario-artifact manifest sid :trace))
             (shot-digest (if shot (file-sha256 (ea-path shot)) ""))
             (trace-digest (if trace (file-sha256 (ea-path trace)) ""))
             (replay (format nil "WEB_EVIDENCE_COMMAND='~A' SCENARIO=~A cd e2e && ./run-e2e.sh" deterministic sid))
             (ready (and shot trace (canonical-playwright-command-p command))))
        (push (make-playwright-replay-card
               :scenario-id sid
               :command command
               :command-hash (command-fingerprint command)
               :replay-command replay
               :screenshot-digest shot-digest
               :trace-digest trace-digest
               :ready-p (not (null ready)))
              cards)))))

(defun build-playwright-evidence-pack-index (artifacts-dir command)
  (declare (type string artifacts-dir command)
           (optimize (safety 3)))
  (let* ((manifest (compile-playwright-evidence-manifest artifacts-dir command))
         (missing (%missing-s1-s6 manifest))
         (command-ok (canonical-playwright-command-p command))
         (scenario-count (length *playwright-required-scenarios*))
         (artifact-count (length (rem-artifacts manifest)))
         (attest-rows (build-playwright-attest-rows manifest))
         (replay-cards (build-playwright-replay-cards manifest command))
         (command-table (list (cons :deterministic *playwright-deterministic-command*)
                              (cons :provided command)))
         (pass (and command-ok (null missing))))
    (make-playwright-evidence-pack-index
     :pass-p pass
     :command-match-p command-ok
     :command-hash (command-fingerprint command)
     :scenario-count scenario-count
     :artifact-count artifact-count
     :missing-scenarios missing
     :attest-rows attest-rows
     :replay-cards replay-cards
     :command-table command-table
     :detail (format nil "command_ok=~A missing=~D artifacts=~D"
                     command-ok (length missing) artifact-count)
     :timestamp (get-universal-time))))

(defun %rows->json (rows)
  (declare (type list rows))
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for row in rows
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out
                       "{\"scenario\":\"~A\",\"complete\":~A,\"screenshot_digest\":\"~A\",\"trace_digest\":\"~A\"}"
                       (pear-scenario-id row)
                       (if (pear-complete-p row) "true" "false")
                       (pear-screenshot-digest row)
                       (pear-trace-digest row))))
    (write-string "]" out)))

(defun %string-list->json (items)
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for item in items
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out "\"~A\"" item)))
    (write-string "]" out)))

(defun %replay-cards->json (cards)
  (with-output-to-string (out)
    (write-string "[" out)
    (loop for card in cards
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (format out
                       "{\"scenario\":\"~A\",\"command\":\"~A\",\"command_hash\":~D,\"replay_command\":\"~A\",\"screenshot_digest\":\"~A\",\"trace_digest\":\"~A\",\"ready\":~A}"
                       (pprc-scenario-id card)
                       (pprc-command card)
                       (pprc-command-hash card)
                       (pprc-replay-command card)
                       (pprc-screenshot-digest card)
                       (pprc-trace-digest card)
                       (if (pprc-ready-p card) "true" "false"))))
    (write-string "]" out)))

(defun playwright-evidence-pack-index->json (index)
  (declare (type playwright-evidence-pack-index index))
  (with-output-to-string (out)
    (format out
            "{\"pass\":~A,\"command_match\":~A,\"command_hash\":~D,\"scenario_count\":~D,\"artifact_count\":~D,\"missing\":~D,\"missing_scenarios\":~A,\"command_table\":{\"deterministic\":\"~A\",\"provided\":\"~A\"},\"attest_rows\":~A,\"replay_cards\":~A,\"detail\":\"~A\",\"timestamp\":~D}"
            (if (pepi-pass-p index) "true" "false")
            (if (pepi-command-match-p index) "true" "false")
            (pepi-command-hash index)
            (pepi-scenario-count index)
            (pepi-artifact-count index)
            (length (pepi-missing-scenarios index))
            (%string-list->json (pepi-missing-scenarios index))
            (cdr (assoc :deterministic (pepi-command-table index)))
            (cdr (assoc :provided (pepi-command-table index)))
            (%rows->json (pepi-attest-rows index))
            (%replay-cards->json (pepi-replay-cards index))
            (pepi-detail index)
            (pepi-timestamp index))))
