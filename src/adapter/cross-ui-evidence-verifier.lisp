;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cross-ui-evidence-verifier.lisp — Typed verifier for Playwright + mcp-tui-driver evidence
;;;
;;; Validates deterministic command manifests, required artifacts,
;;; and scenario coverage matrix for cross-UI parity gates.

(in-package #:orrery/adapter)

(deftype evidence-runner-kind ()
  '(member :playwright-web :mcp-tui-driver))

(deftype scenario-status ()
  '(member :pass :fail :skip :missing))

(deftype evidence-artifact-kind ()
  '(member :machine-report :screenshot :trace :transcript :asciicast))

(deftype evidence-finding-severity ()
  '(member :critical :warning :info))

(deftype cross-ui-parity-verdict ()
  '(member :match :mismatch :missing-web :missing-tui))

(defstruct (scenario-evidence
             (:constructor make-scenario-evidence
                 (&key scenario-id status detail))
             (:conc-name sce-))
  "One scenario result from a test runner summary."
  (scenario-id "" :type string)
  (status :missing :type scenario-status)
  (detail "" :type string))

(defstruct (evidence-artifact
             (:constructor make-evidence-artifact
                 (&key scenario-id artifact-kind path present-p detail))
             (:conc-name ea-))
  "One artifact expected/produced by a runner.
SCENARIO-ID is empty string for global artifacts."
  (scenario-id "" :type string)
  (artifact-kind :machine-report :type evidence-artifact-kind)
  (path "" :type string)
  (present-p nil :type boolean)
  (detail "" :type string))

(defstruct (runner-evidence-manifest
             (:constructor make-runner-evidence-manifest
                 (&key runner-id runner-kind command scenarios artifacts timestamp))
             (:conc-name rem-))
  "Complete evidence manifest emitted by one UI runner."
  (runner-id "" :type string)
  (runner-kind :playwright-web :type evidence-runner-kind)
  (command "" :type string)
  (scenarios '() :type list)
  (artifacts '() :type list)
  (timestamp 0 :type (integer 0)))

(defstruct (evidence-finding
             (:constructor make-evidence-finding
                 (&key severity code message))
             (:conc-name ef-))
  "One verifier finding."
  (severity :info :type evidence-finding-severity)
  (code "" :type string)
  (message "" :type string))

(defstruct (scenario-coverage-row
             (:constructor make-scenario-coverage-row
                 (&key scenario-id passed-p status artifact-ok-p missing-artifacts))
             (:conc-name scr-))
  "Coverage row for one required scenario."
  (scenario-id "" :type string)
  (passed-p nil :type boolean)
  (status :missing :type scenario-status)
  (artifact-ok-p nil :type boolean)
  (missing-artifacts '() :type list))

(defstruct (evidence-compliance-report
             (:constructor make-evidence-compliance-report
                 (&key runner-id runner-kind pass-p findings
                       coverage required-scenarios-covered
                       required-scenarios-total timestamp))
             (:conc-name ecr-))
  "Compliance report for one runner manifest."
  (runner-id "" :type string)
  (runner-kind :playwright-web :type evidence-runner-kind)
  (pass-p nil :type boolean)
  (findings '() :type list)
  (coverage '() :type list)
  (required-scenarios-covered 0 :type (integer 0))
  (required-scenarios-total 0 :type (integer 0))
  (timestamp 0 :type (integer 0)))

(defstruct (parity-row
             (:constructor make-parity-row
                 (&key web-scenario tui-scenario
                       web-pass-p tui-pass-p verdict detail))
             (:conc-name pry-))
  "One cross-UI parity row between mapped scenarios."
  (web-scenario "" :type string)
  (tui-scenario "" :type string)
  (web-pass-p nil :type boolean)
  (tui-pass-p nil :type boolean)
  (verdict :mismatch :type cross-ui-parity-verdict)
  (detail "" :type string))

(defstruct (evidence-parity-report
             (:constructor make-evidence-parity-report
                 (&key pass-p rows match-count mismatch-count missing-count))
             (:conc-name epr-))
  "Cross-UI parity report from scenario mapping."
  (pass-p nil :type boolean)
  (rows '() :type list)
  (match-count 0 :type (integer 0))
  (mismatch-count 0 :type (integer 0))
  (missing-count 0 :type (integer 0)))

(defstruct (cross-ui-evidence-report
             (:constructor make-cross-ui-evidence-report
                 (&key pass-p web-report tui-report parity-report timestamp))
             (:conc-name cuer-))
  "Top-level verification result consumed by parity gates."
  (pass-p nil :type boolean)
  (web-report (make-evidence-compliance-report) :type evidence-compliance-report)
  (tui-report (make-evidence-compliance-report) :type evidence-compliance-report)
  (parity-report (make-evidence-parity-report) :type evidence-parity-report)
  (timestamp 0 :type (integer 0)))

(defparameter *default-web-scenarios*
  '("S1" "S2" "S3" "S4" "S5" "S6")
  "Required Playwright scenarios for Epic 4 baseline.")

(defparameter *default-tui-scenarios*
  '("T1" "T2" "T3" "T4" "T5" "T6")
  "Required mcp-tui-driver scenarios for Epic 3 baseline.")

(defparameter *default-scenario-mapping*
  '(("S1" . "T1")
    ("S2" . "T2")
    ("S3" . "T3")
    ("S4" . "T4")
    ("S5" . "T5")
    ("S6" . "T6"))
  "Default web↔tui scenario mapping for parity matrix.")

(defparameter *web-required-artifacts*
  '((:machine-report . :global)
    (:screenshot . :per-scenario)
    (:trace . :per-scenario))
  "Required artifact policy for Playwright evidence.")

(defparameter *tui-required-artifacts*
  '((:machine-report . :global)
    (:asciicast . :global)
    (:screenshot . :per-scenario)
    (:transcript . :per-scenario))
  "Required artifact policy for mcp-tui-driver evidence.")

(defparameter *expected-web-command*
  "cd e2e && ./run-e2e.sh"
  "Deterministic command contract for web evidence.")

(defparameter *expected-tui-command*
  "make e2e-tui"
  "Deterministic command contract for TUI evidence.")

(declaim (ftype (function (string) (values string &optional)) normalize-scenario-id)
         (ftype (function (runner-evidence-manifest string)
                          (values (or null scenario-evidence) &optional))
                find-scenario)
         (ftype (function (runner-evidence-manifest evidence-artifact-kind
                                  &key (:scenario-id string))
                          (values boolean &optional))
                artifact-present-p)
         (ftype (function (runner-evidence-manifest list list list string)
                          (values evidence-compliance-report &optional))
                verify-runner-evidence)
         (ftype (function (evidence-compliance-report evidence-compliance-report
                                  &key (:mapping list))
                          (values evidence-parity-report &optional))
                build-evidence-parity-report)
         (ftype (function (runner-evidence-manifest runner-evidence-manifest
                                  &key (:timestamp (integer 0)))
                          (values cross-ui-evidence-report &optional))
                verify-cross-ui-evidence)
         (ftype (function (evidence-compliance-report) (values string &optional))
                evidence-compliance-report->json)
         (ftype (function (evidence-parity-report) (values string &optional))
                evidence-parity-report->json)
         (ftype (function (cross-ui-evidence-report) (values string &optional))
                cross-ui-evidence-report->json))

(defun normalize-scenario-id (raw)
  "Extract stable scenario ID (e.g. \"S1\" or \"T4\") from a label."
  (declare (type string raw))
  (let* ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) raw))
         (colon-pos (position #\: trimmed)))
    (if colon-pos
        (subseq trimmed 0 colon-pos)
        trimmed)))

(defun find-scenario (manifest scenario-id)
  "Find scenario evidence row by normalized ID."
  (declare (type runner-evidence-manifest manifest)
           (type string scenario-id))
  (find scenario-id
        (rem-scenarios manifest)
        :key (lambda (s) (normalize-scenario-id (sce-scenario-id s)))
        :test #'string=))

(defun artifact-present-p (manifest artifact-kind &key (scenario-id ""))
  "Return true when at least one matching artifact is marked present."
  (declare (type runner-evidence-manifest manifest)
           (type evidence-artifact-kind artifact-kind)
           (type string scenario-id))
  (some (lambda (artifact)
          (and (eq artifact-kind (ea-artifact-kind artifact))
               (ea-present-p artifact)
               (if (string= scenario-id "")
                   (string= "" (ea-scenario-id artifact))
                   (string= scenario-id
                            (normalize-scenario-id (ea-scenario-id artifact))))))
        (rem-artifacts manifest)))

(defun %required-kinds-for-scope (required-artifacts scope)
  (declare (type list required-artifacts))
  (loop for (kind . artifact-scope) in required-artifacts
        when (eq artifact-scope scope)
          collect kind))

(defun %row-missing-artifacts (manifest scenario-id required-artifacts)
  (let ((missing '()))
    (dolist (kind (%required-kinds-for-scope required-artifacts :per-scenario))
      (unless (artifact-present-p manifest kind :scenario-id scenario-id)
        (push kind missing)))
    (nreverse missing)))

(defun %command-finding (actual expected)
  (if (string= actual expected)
      nil
      (make-evidence-finding
       :severity :critical
       :code "deterministic-command-mismatch"
       :message (format nil "Expected command '~A' but manifest recorded '~A'"
                        expected actual))))

(defun verify-runner-evidence (manifest required-scenarios required-artifacts
                                 required-global-artifacts expected-command)
  "Verify one runner evidence manifest for command+artifact+coverage compliance."
  (declare (type runner-evidence-manifest manifest)
           (type list required-scenarios required-artifacts required-global-artifacts)
           (type string expected-command))
  (let ((findings '())
        (rows '())
        (covered 0))
    (let ((cmd-finding (%command-finding (rem-command manifest) expected-command)))
      (when cmd-finding
        (push cmd-finding findings)))

    (dolist (kind required-global-artifacts)
      (unless (artifact-present-p manifest kind)
        (push (make-evidence-finding
               :severity :critical
               :code "missing-global-artifact"
               :message (format nil "Missing required global artifact ~A" kind))
              findings)))

    (dolist (scenario-id required-scenarios)
      (let* ((scenario (find-scenario manifest scenario-id))
             (status (if scenario (sce-status scenario) :missing))
             (passed-p (eq :pass status))
             (missing (%row-missing-artifacts manifest scenario-id required-artifacts))
             (artifact-ok-p (null missing)))
        (when passed-p (incf covered))
        (unless scenario
          (push (make-evidence-finding
                 :severity :critical
                 :code "missing-scenario"
                 :message (format nil "Required scenario ~A not present in summary"
                                  scenario-id))
                findings))
        (when (and scenario (not passed-p))
          (push (make-evidence-finding
                 :severity :critical
                 :code "scenario-not-pass"
                 :message (format nil "Scenario ~A status is ~A"
                                  scenario-id status))
                findings))
        (when missing
          (push (make-evidence-finding
                 :severity :critical
                 :code "missing-scenario-artifacts"
                 :message (format nil "Scenario ~A missing artifacts: ~{~A~^, ~}"
                                  scenario-id missing))
                findings))
        (push (make-scenario-coverage-row
               :scenario-id scenario-id
               :passed-p passed-p
               :status status
               :artifact-ok-p artifact-ok-p
               :missing-artifacts missing)
              rows)))

    (let ((critical-count (count :critical findings :key #'ef-severity)))
      (make-evidence-compliance-report
       :runner-id (rem-runner-id manifest)
       :runner-kind (rem-runner-kind manifest)
       :pass-p (zerop critical-count)
       :findings (nreverse findings)
       :coverage (nreverse rows)
       :required-scenarios-covered covered
       :required-scenarios-total (length required-scenarios)
       :timestamp (rem-timestamp manifest)))))

(defun %coverage-row-by-id (report scenario-id)
  (declare (type evidence-compliance-report report)
           (type string scenario-id))
  (find scenario-id
        (ecr-coverage report)
        :key #'scr-scenario-id
        :test #'string=))

(defun build-evidence-parity-report (web-report tui-report &key (mapping *default-scenario-mapping*))
  "Build cross-UI parity matrix from web/tui coverage reports."
  (declare (type evidence-compliance-report web-report tui-report)
           (type list mapping))
  (let ((rows '())
        (match-count 0)
        (mismatch-count 0)
        (missing-count 0))
    (dolist (pair mapping)
      (let* ((web-id (car pair))
             (tui-id (cdr pair))
             (web-row (%coverage-row-by-id web-report web-id))
             (tui-row (%coverage-row-by-id tui-report tui-id))
             (web-pass (and web-row (scr-passed-p web-row) (scr-artifact-ok-p web-row)))
             (tui-pass (and tui-row (scr-passed-p tui-row) (scr-artifact-ok-p tui-row)))
             (verdict (cond
                        ((null web-row) :missing-web)
                        ((null tui-row) :missing-tui)
                        ((and web-pass tui-pass) :match)
                        (t :mismatch)))
             (detail (case verdict
                       (:missing-web (format nil "Web scenario ~A missing" web-id))
                       (:missing-tui (format nil "TUI scenario ~A missing" tui-id))
                       (:match "Both scenarios satisfied parity requirements")
                       (otherwise (format nil "Status mismatch web=~A tui=~A"
                                          (if web-row (scr-status web-row) :missing)
                                          (if tui-row (scr-status tui-row) :missing))))))
        (ecase verdict
          (:match (incf match-count))
          (:mismatch (incf mismatch-count))
          ((:missing-web :missing-tui) (incf missing-count)))
        (push (make-parity-row
               :web-scenario web-id
               :tui-scenario tui-id
               :web-pass-p web-pass
               :tui-pass-p tui-pass
               :verdict verdict
               :detail detail)
              rows)))
    (make-evidence-parity-report
     :pass-p (and (zerop mismatch-count) (zerop missing-count))
     :rows (nreverse rows)
     :match-count match-count
     :mismatch-count mismatch-count
     :missing-count missing-count)))

(defun verify-cross-ui-evidence (web-manifest tui-manifest &key (timestamp 0))
  "Run full cross-UI evidence verification for Playwright + mcp-tui-driver manifests."
  (declare (type runner-evidence-manifest web-manifest tui-manifest)
           (type (integer 0) timestamp))
  (let* ((web-report (verify-runner-evidence
                      web-manifest
                      *default-web-scenarios*
                      *web-required-artifacts*
                      '(:machine-report)
                      *expected-web-command*))
         (tui-report (verify-runner-evidence
                      tui-manifest
                      *default-tui-scenarios*
                      *tui-required-artifacts*
                      '(:machine-report :asciicast)
                      *expected-tui-command*))
         (parity-report (build-evidence-parity-report web-report tui-report))
         (pass-p (and (ecr-pass-p web-report)
                      (ecr-pass-p tui-report)
                      (epr-pass-p parity-report))))
    (make-cross-ui-evidence-report
     :pass-p pass-p
     :web-report web-report
     :tui-report tui-report
     :parity-report parity-report
     :timestamp timestamp)))

(defun evidence-compliance-report->json (report)
  "Serialize evidence-compliance-report with stable key ordering."
  (declare (type evidence-compliance-report report))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"runner_id\":" s)
    (emit-json-string (ecr-runner-id report) s)
    (write-string ",\"runner_kind\":" s)
    (emit-json-string (string-downcase (symbol-name (ecr-runner-kind report))) s)
    (write-string ",\"pass\":" s)
    (write-string (if (ecr-pass-p report) "true" "false") s)
    (write-string ",\"required_scenarios\":" s)
    (format s "~D" (ecr-required-scenarios-total report))
    (write-string ",\"covered_scenarios\":" s)
    (format s "~D" (ecr-required-scenarios-covered report))
    (write-string ",\"findings\":[" s)
    (let ((first t))
      (dolist (finding (ecr-findings report))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{" s)
        (write-string "\"severity\":" s)
        (emit-json-string (string-downcase (symbol-name (ef-severity finding))) s)
        (write-string ",\"code\":" s)
        (emit-json-string (ef-code finding) s)
        (write-string ",\"message\":" s)
        (emit-json-string (ef-message finding) s)
        (write-string "}" s)))
    (write-string "]}" s)))

(defun evidence-parity-report->json (report)
  "Serialize evidence-parity-report with stable key ordering."
  (declare (type evidence-parity-report report))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"pass\":" s)
    (write-string (if (epr-pass-p report) "true" "false") s)
    (write-string ",\"matches\":" s)
    (format s "~D" (epr-match-count report))
    (write-string ",\"mismatches\":" s)
    (format s "~D" (epr-mismatch-count report))
    (write-string ",\"missing\":" s)
    (format s "~D" (epr-missing-count report))
    (write-string ",\"rows\":[" s)
    (let ((first t))
      (dolist (row (epr-rows report))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{" s)
        (write-string "\"web\":" s)
        (emit-json-string (pry-web-scenario row) s)
        (write-string ",\"tui\":" s)
        (emit-json-string (pry-tui-scenario row) s)
        (write-string ",\"verdict\":" s)
        (emit-json-string (string-downcase (symbol-name (pry-verdict row))) s)
        (write-string ",\"detail\":" s)
        (emit-json-string (pry-detail row) s)
        (write-string "}" s)))
    (write-string "]}" s)))

(defun cross-ui-evidence-report->json (report)
  "Serialize top-level cross-ui-evidence-report."
  (declare (type cross-ui-evidence-report report))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"pass\":" s)
    (write-string (if (cuer-pass-p report) "true" "false") s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (cuer-timestamp report))
    (write-string ",\"web\":" s)
    (write-string (evidence-compliance-report->json (cuer-web-report report)) s)
    (write-string ",\"tui\":" s)
    (write-string (evidence-compliance-report->json (cuer-tui-report report)) s)
    (write-string ",\"parity\":" s)
    (write-string (evidence-parity-report->json (cuer-parity-report report)) s)
    (write-string "}" s)))
