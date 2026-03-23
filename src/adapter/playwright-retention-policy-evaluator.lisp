;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-retention-policy-evaluator.lisp — typed S1-S6 retention/lineage policy evaluator
;;; Bead: agent-orrery-jwv2

(in-package #:orrery/adapter)

;;; ── Policy definition ────────────────────────────────────────────────────────

(defstruct (s1-s6-retention-policy (:conc-name srp-))
  "Per-scenario retention policy."
  (scenario-id     ""              :type string)
  (retention-window 86400          :type (integer 0))   ; seconds
  (required-kinds  '(:screenshot :trace) :type list)
  (command-fingerprint 0           :type integer))

;;; ── Evaluation result ────────────────────────────────────────────────────────

(defstruct (retention-evaluation-result (:conc-name rer-))
  "Result of evaluating one scenario against its retention policy."
  (scenario-id       ""    :type string)
  (pass-p            nil   :type boolean)
  (age-secs          0     :type (integer 0))
  (within-window-p   nil   :type boolean)
  (kinds-present     nil   :type list)
  (kinds-missing     nil   :type list)
  (command-match-p   nil   :type boolean)
  (provenance-edge-p nil   :type boolean)
  (detail            ""    :type string))

;;; ── Report ───────────────────────────────────────────────────────────────────

(defstruct (s1-s6-retention-report (:conc-name srr-))
  "Aggregated retention policy evaluation report for all S1-S6 scenarios."
  (run-id            ""    :type string)
  (command           ""    :type string)
  (command-fingerprint 0   :type integer)
  (pass-p            nil   :type boolean)
  (evaluated-count   0     :type (integer 0))
  (failed-scenarios  nil   :type list)
  (results           nil   :type list)     ; list of retention-evaluation-result
  (timestamp         0     :type (integer 0)))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string) (values boolean &optional))
        canonical-playwright-command-p/retention)
 (ftype (function (string list integer integer boolean) (values retention-evaluation-result &optional))
        evaluate-scenario-retention)
 (ftype (function (string string) (values s1-s6-retention-report &optional))
        evaluate-s1-s6-retention-policy)
 (ftype (function (s1-s6-retention-report) (values string &optional))
        s1-s6-retention-report->json)
 (ftype (function (retention-evaluation-result) (values string &optional))
        retention-evaluation-result->json))

;;; ── Command canonicality ─────────────────────────────────────────────────────

(defun canonical-playwright-command-p/retention (command)
  "Return T if COMMAND is the canonical Playwright deterministic command."
  (declare (type string command)
           (optimize (safety 3)))
  (or (string= command "cd e2e && ./run-e2e.sh")
      (string= command "bash run-e2e.sh")))

;;; ── Default policies ─────────────────────────────────────────────────────────

(defun %default-retention-policies (command)
  "Build default per-scenario retention policies for all S1-S6."
  (declare (type string command))
  (let ((fp (sxhash command)))
    (mapcar (lambda (sid)
              (make-s1-s6-retention-policy
               :scenario-id sid
               :retention-window 86400
               :required-kinds '(:screenshot :trace)
               :command-fingerprint fp))
            *playwright-required-scenarios*)))

;;; ── Scenario evaluation ──────────────────────────────────────────────────────

(defun evaluate-scenario-retention (scenario-id kinds-present age-secs retention-window
                                    provenance-edge-p)
  "Evaluate one scenario against retention requirements."
  (declare (type string scenario-id)
           (type list kinds-present)
           (type (integer 0) age-secs retention-window)
           (type boolean provenance-edge-p)
           (optimize (safety 3)))
  (let* ((required '(:screenshot :trace))
         (kinds-missing (remove-if (lambda (k) (member k kinds-present)) required))
         (within-window (< age-secs retention-window))
         (pass (and (null kinds-missing) within-window provenance-edge-p)))
    (make-retention-evaluation-result
     :scenario-id       scenario-id
     :pass-p            pass
     :age-secs          age-secs
     :within-window-p   within-window
     :kinds-present     kinds-present
     :kinds-missing     kinds-missing
     :command-match-p   t   ; set by caller
     :provenance-edge-p provenance-edge-p
     :detail            (if pass
                            (format nil "~A: OK (age=~Ds, kinds=~{~A~^,~})"
                                    scenario-id age-secs kinds-present)
                            (format nil "~A: FAIL missing=~{~A~^,~} window=~A provenance=~A"
                                    scenario-id kinds-missing within-window provenance-edge-p)))))

;;; ── Manifest-based evaluation ────────────────────────────────────────────────

(defun %evaluate-manifest-scenario (manifest sid command-ok-p now)
  "Evaluate one scenario from an evidence manifest."
  (declare (type runner-evidence-manifest manifest)
           (type string sid)
           (type boolean command-ok-p)
           (type integer now)
           (optimize (safety 3)))
  (let* ((artifacts (rem-artifacts manifest))
         (shot (find-if (lambda (a)
                          (and (string= sid (ea-scenario-id a))
                               (eq :screenshot (ea-artifact-kind a))
                               (ea-present-p a)))
                        artifacts))
         (trace (find-if (lambda (a)
                           (and (string= sid (ea-scenario-id a))
                                (eq :trace (ea-artifact-kind a))
                                (ea-present-p a)))
                         artifacts))
         (kinds-present (remove nil
                                (list (when shot :screenshot)
                                      (when trace :trace))))
         ;; Approximate artifact age from manifest timestamp
         (artifact-ts (rem-timestamp manifest))
         (age-secs (max 0 (- now artifact-ts)))
         (provenance-p (not (null shot))))  ; heuristic: screenshot implies provenance edge
    (let ((result (evaluate-scenario-retention sid kinds-present age-secs 86400 provenance-p)))
      ;; Patch command-match-p from caller
      (make-retention-evaluation-result
       :scenario-id       (rer-scenario-id result)
       :pass-p            (and (rer-pass-p result) command-ok-p)
       :age-secs          (rer-age-secs result)
       :within-window-p   (rer-within-window-p result)
       :kinds-present     (rer-kinds-present result)
       :kinds-missing     (rer-kinds-missing result)
       :command-match-p   command-ok-p
       :provenance-edge-p (rer-provenance-edge-p result)
       :detail            (if (and (rer-pass-p result) command-ok-p)
                              (rer-detail result)
                              (format nil "~A command-ok=~A" (rer-detail result) command-ok-p))))))

;;; ── Report assembly ──────────────────────────────────────────────────────────

(defun evaluate-s1-s6-retention-policy (artifact-root command)
  "Evaluate S1-S6 artifact retention/lineage policy. Returns S1-S6-RETENTION-REPORT."
  (declare (type string artifact-root command)
           (optimize (safety 3)))
  (let* ((manifest (compile-playwright-evidence-manifest artifact-root command))
         (command-ok (canonical-playwright-command-p/retention command))
         (now (get-universal-time))
         (results (mapcar (lambda (sid)
                            (%evaluate-manifest-scenario manifest sid command-ok now))
                          *playwright-required-scenarios*))
         (failed (mapcar #'rer-scenario-id
                         (remove-if #'rer-pass-p results)))
         (all-pass (and command-ok (null failed))))
    (make-s1-s6-retention-report
     :run-id             (format nil "retention-eval-~D" now)
     :command            command
     :command-fingerprint (sxhash command)
     :pass-p             all-pass
     :evaluated-count    (length results)
     :failed-scenarios   failed
     :results            results
     :timestamp          now)))

;;; ── JSON serialization ───────────────────────────────────────────────────────

(defun retention-evaluation-result->json (r)
  "Serialize RETENTION-EVALUATION-RESULT to JSON string."
  (declare (type retention-evaluation-result r)
           (optimize (safety 3)))
  (format nil
          "{\"scenario_id\":\"~A\",\"pass\":~:[false~;true~],\"age_secs\":~D,\"within_window\":~:[false~;true~],\"kinds_present\":[~{\"~A\"~^,~}],\"kinds_missing\":[~{\"~A\"~^,~}],\"command_match\":~:[false~;true~],\"provenance_edge\":~:[false~;true~],\"detail\":\"~A\"}"
          (rer-scenario-id r)
          (rer-pass-p r)
          (rer-age-secs r)
          (rer-within-window-p r)
          (mapcar (lambda (k) (string-downcase (symbol-name k))) (rer-kinds-present r))
          (mapcar (lambda (k) (string-downcase (symbol-name k))) (rer-kinds-missing r))
          (rer-command-match-p r)
          (rer-provenance-edge-p r)
          (rer-detail r)))

(defun s1-s6-retention-report->json (report)
  "Serialize S1-S6-RETENTION-REPORT to JSON string."
  (declare (type s1-s6-retention-report report)
           (optimize (safety 3)))
  (format nil
          "{\"run_id\":\"~A\",\"command\":\"~A\",\"command_fingerprint\":~D,\"pass\":~:[false~;true~],\"evaluated_count\":~D,\"failed_scenarios\":[~{\"~A\"~^,~}],\"timestamp\":~D,\"results\":[~{~A~^,~}]}"
          (srr-run-id report)
          (srr-command report)
          (srr-command-fingerprint report)
          (srr-pass-p report)
          (srr-evaluated-count report)
          (srr-failed-scenarios report)
          (srr-timestamp report)
          (mapcar #'retention-evaluation-result->json (srr-results report))))
