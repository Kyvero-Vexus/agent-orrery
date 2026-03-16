;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cross-ui-parity-suite.lisp — Cross-UI parity suite + conformance report
;;;
;;; Bead: agent-orrery-eb0.6.3

(in-package #:orrery/adapter)

(deftype conformance-target ()
  '(member :tui :web :mcclim))

(defstruct (target-conformance-row (:conc-name tcr-))
  "Conformance status for one UI target."
  (target :tui :type conformance-target)
  (contract-pass-p nil :type boolean)
  (contract-violations 0 :type fixnum)
  (parity-pass-p nil :type boolean)
  (v2-module-pass-p nil :type boolean)
  (v2-missing-count 0 :type fixnum)
  (evidence-required-p nil :type boolean)
  (evidence-pass-p nil :type boolean)
  (overall-pass-p nil :type boolean)
  (detail "" :type string))

(defstruct (cross-ui-conformance-report (:conc-name cuc-))
  "Typed conformance report for Epic-6 parity gating."
  (pass-p nil :type boolean)
  (target-rows nil :type list)
  (contract-results nil :type list)
  (pairwise-parity-results nil :type list)
  (evidence-report nil :type (or null cross-ui-evidence-report))
  (required-target-count 0 :type fixnum)
  (passing-target-count 0 :type fixnum)
  (timestamp 0 :type integer)
  (deterministic-commands nil :type list))

(declaim
 (ftype (function (list conformance-target) (values (or null contract-verification) &optional))
        find-contract-verification)
 (ftype (function (list conformance-target) (values list &optional))
        parity-reports-for-target)
 (ftype (function ((or null cross-ui-evidence-report) conformance-target)
                  (values boolean &optional))
        target-evidence-pass-p)
 (ftype (function (trace-collector &key (:timestamp integer)
                                   (:web-manifest (or null runner-evidence-manifest))
                                   (:tui-manifest (or null runner-evidence-manifest))
                                   (:required-targets list))
                  (values cross-ui-conformance-report &optional))
        run-cross-ui-parity-suite)
 (ftype (function (target-conformance-row) (values string &optional))
        target-conformance-row->json)
 (ftype (function (cross-ui-conformance-report) (values string &optional))
        cross-ui-conformance-report->json)
 (ftype (function () (values list &optional))
        cross-ui-deterministic-commands))

(defun find-contract-verification (contract-results target)
  (declare (type list contract-results)
           (type conformance-target target)
           (optimize (safety 3)))
  (find target contract-results :key #'cv-target :test #'eq))

(defun parity-reports-for-target (parity-results target)
  (declare (type list parity-results)
           (type conformance-target target)
           (optimize (safety 3)))
  (remove-if-not
   (lambda (report)
     (let ((name (par-profile-name report))
           (target-label (string-downcase (symbol-name target))))
       (or (search target-label name :test #'char-equal)
           (eq target (par-target report)))))
   parity-results))

(defun target-evidence-pass-p (evidence-report target)
  (declare (type (or null cross-ui-evidence-report) evidence-report)
           (type conformance-target target)
           (optimize (safety 3)))
  (cond
    ((eq target :mcclim) t)
    ((null evidence-report) nil)
    ((eq target :web) (ecr-pass-p (cuer-web-report evidence-report)))
    ((eq target :tui) (ecr-pass-p (cuer-tui-report evidence-report)))
    (t nil)))

(defun cross-ui-deterministic-commands ()
  "Canonical deterministic command manifest for parity evidence collection."
  (declare (optimize (safety 3)))
  (list
   "cd e2e && ./run-e2e.sh"
   "make e2e-tui"
   "export LD_LIBRARY_PATH=\"/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH\" && sbcl --eval '(load \"/home/slime/quicklisp/setup.lisp\")' --script ci/run-tests.lisp"))

(defun %target-v2-symbol-contract (target)
  "Required v2 symbols for each UI surface.
Returns list of (package-name . symbol-name)."
  (declare (type conformance-target target) (optimize (safety 3)))
  (ecase target
    (:tui '(("ORRERY/TUI" . "BUILD-COST-OPTIMIZER-CARD")
            ("ORRERY/TUI" . "BUILD-CAPACITY-PLANNER-CARD")))
    (:web '(("ORRERY/WEB" . "RENDER-AUDIT-TRAIL-HTML")
            ("ORRERY/WEB" . "RENDER-ANALYTICS-HTML")
            ("ORRERY/WEB" . "AUDIT-TRAIL-JSON")
            ("ORRERY/WEB" . "ANALYTICS-JSON")))
    (:mcclim '(("ORRERY/MCCLIM" . "DISPLAY-COST-OPTIMIZER")
               ("ORRERY/MCCLIM" . "DISPLAY-CAPACITY-PLANNER")
               ("ORRERY/MCCLIM" . "DISPLAY-SESSION-ANALYTICS")
               ("ORRERY/MCCLIM" . "DISPLAY-AUDIT-TRAIL")))))

(defun %v2-symbol-fboundp (pkg-name sym-name)
  (declare (type string pkg-name sym-name) (optimize (safety 3)))
  (let ((pkg (find-package pkg-name)))
    (when pkg
      (multiple-value-bind (sym present-p) (find-symbol sym-name pkg)
        (and present-p (fboundp sym))))))

(defun %v2-module-check (target)
  "Return (values pass-p missing-symbols)."
  (declare (type conformance-target target) (optimize (safety 3)))
  (let* ((required (%target-v2-symbol-contract target))
         (missing (remove-if (lambda (pair)
                               (%v2-symbol-fboundp (car pair) (cdr pair)))
                             required)))
    (values (null missing) missing)))

(defun %target-row (target contract-results parity-results evidence-report)
  (declare (type conformance-target target)
           (type list contract-results parity-results)
           (type (or null cross-ui-evidence-report) evidence-report)
           (optimize (safety 3)))
  (multiple-value-bind (v2-pass missing-v2)
      (%v2-module-check target)
    (let* ((contract (find-contract-verification contract-results target))
           (contract-pass (and contract (cv-overall-pass-p contract)))
           (contract-violations (if contract (cv-violated-count contract) 999))
           (target-parity (parity-reports-for-target parity-results target))
           ;; For cross-target parity we accept kind-level parity (fail-count=0)
           ;; even when raw trace diff hash/seq identities differ between UIs.
           (parity-pass (every (lambda (report)
                                 (zerop (par-fail-count report)))
                               target-parity))
           (evidence-required (not (null (member target '(:web :tui) :test #'eq))))
           (evidence-pass (target-evidence-pass-p evidence-report target))
           (overall (and contract-pass
                         parity-pass
                         v2-pass
                         (if evidence-required evidence-pass t))))
      (make-target-conformance-row
       :target target
       :contract-pass-p contract-pass
       :contract-violations contract-violations
       :parity-pass-p parity-pass
       :v2-module-pass-p v2-pass
       :v2-missing-count (length missing-v2)
       :evidence-required-p evidence-required
       :evidence-pass-p evidence-pass
       :overall-pass-p overall
       :detail (format nil "target=~A contract=~A parity=~A v2=~A missing=~D evidence=~A"
                       target
                       (if contract-pass "pass" "fail")
                       (if parity-pass "pass" "fail")
                       (if v2-pass "pass" "fail")
                       (length missing-v2)
                       (if evidence-pass "pass" "fail"))))))

(defun run-cross-ui-parity-suite (collector
                                  &key (timestamp 0)
                                       web-manifest
                                       tui-manifest
                                       (required-targets '(:tui :web :mcclim)))
  "Run the cross-UI parity suite and produce a typed conformance report.

Combines:
- trace contract verification (all targets)
- pairwise parity assertions (all available target pairs)
- web+tui evidence compliance report (Playwright + mcp-tui-driver)
"
  (declare (type trace-collector collector)
           (type integer timestamp)
           (type list required-targets)
           (type (or null runner-evidence-manifest) web-manifest tui-manifest)
           (optimize (safety 3)))
  (let* ((contract-results (verify-all-contracts collector *standard-trace-contracts* timestamp))
         (pairwise-parity (cross-ui-parity-matrix collector timestamp))
         (evidence-report (and web-manifest tui-manifest
                               (verify-cross-ui-evidence web-manifest tui-manifest
                                                         :timestamp timestamp)))
         (rows (mapcar (lambda (target)
                         (%target-row target contract-results pairwise-parity evidence-report))
                       required-targets))
         (passing (count t rows :key #'tcr-overall-pass-p))
         (pass-p (= passing (length rows))))
    (make-cross-ui-conformance-report
     :pass-p pass-p
     :target-rows rows
     :contract-results contract-results
     :pairwise-parity-results pairwise-parity
     :evidence-report evidence-report
     :required-target-count (length required-targets)
     :passing-target-count passing
     :timestamp timestamp
     :deterministic-commands (cross-ui-deterministic-commands))))

(defun target-conformance-row->json (row)
  (declare (type target-conformance-row row)
           (optimize (safety 3)))
  (format nil
          "{\"target\":\"~A\",\"contract_pass\":~A,\"contract_violations\":~D,\"parity_pass\":~A,\"v2_pass\":~A,\"v2_missing\":~D,\"evidence_required\":~A,\"evidence_pass\":~A,\"overall_pass\":~A,\"detail\":\"~A\"}"
          (string-downcase (symbol-name (tcr-target row)))
          (if (tcr-contract-pass-p row) "true" "false")
          (tcr-contract-violations row)
          (if (tcr-parity-pass-p row) "true" "false")
          (if (tcr-v2-module-pass-p row) "true" "false")
          (tcr-v2-missing-count row)
          (if (tcr-evidence-required-p row) "true" "false")
          (if (tcr-evidence-pass-p row) "true" "false")
          (if (tcr-overall-pass-p row) "true" "false")
          (tcr-detail row)))

(defun cross-ui-conformance-report->json (report)
  (declare (type cross-ui-conformance-report report)
           (optimize (safety 3)))
  (format nil
          "{\"pass\":~A,\"required_targets\":~D,\"passing_targets\":~D,\"timestamp\":~D,\"rows\":[~{~A~^,~}],\"commands\":[~{\"~A\"~^,~}]}"
          (if (cuc-pass-p report) "true" "false")
          (cuc-required-target-count report)
          (cuc-passing-target-count report)
          (cuc-timestamp report)
          (mapcar #'target-conformance-row->json (cuc-target-rows report))
          (cuc-deterministic-commands report)))
