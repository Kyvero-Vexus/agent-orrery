;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; cross-framework-evidence-harmonizer.lisp — typed cross-framework evidence schema harmonizer
;;; Bead: agent-orrery-uzma

(in-package #:orrery/adapter)

;;; ── Harmonized scenario row ──────────────────────────────────────────────────

(defstruct (harmonized-scenario-row (:conc-name hsr-))
  "Normalized row for one scenario across Epic 3 (TUI) or Epic 4 (Web) frameworks."
  (scenario-id    ""        :type string)
  (framework      :unknown  :type (member :playwright :mcp-tui :unknown))
  (command        ""        :type string)
  (command-hash   0         :type integer)
  (evidence-ok-p  nil       :type boolean)
  (artifact-count 0         :type (integer 0))
  (digest-key     ""        :type string)
  (detail         ""        :type string))

;;; ── Harmonized envelope ──────────────────────────────────────────────────────

(defstruct (harmonized-evidence-envelope (:conc-name hee-))
  "Cross-framework evidence envelope for closure dashboards."
  (envelope-id    ""    :type string)
  (epic3-rows     nil   :type list)
  (epic4-rows     nil   :type list)
  (epic3-pass-p   nil   :type boolean)
  (epic4-pass-p   nil   :type boolean)
  (overall-pass-p nil   :type boolean)
  (timestamp      0     :type integer)
  (detail         ""    :type string))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (tui-bundle-notarization) (values list &optional))
        harmonize-tui-evidence)
 (ftype (function (playwright-evidence-bundle) (values list &optional))
        harmonize-playwright-evidence)
 (ftype (function (tui-bundle-notarization playwright-evidence-bundle)
                  (values harmonized-evidence-envelope &optional))
        compile-harmonized-envelope)
 (ftype (function (harmonized-evidence-envelope) (values string &optional))
        harmonized-evidence-envelope->json))

;;; ── Harmonizers ──────────────────────────────────────────────────────────────

(defun harmonize-tui-evidence (tui-bundle)
  "Convert TUI-BUNDLE-NOTARIZATION records to harmonized scenario rows."
  (declare (type tui-bundle-notarization tui-bundle)
           (optimize (safety 3)))
  (mapcar (lambda (r)
            (make-harmonized-scenario-row
             :scenario-id    (tnr-scenario-id r)
             :framework      :mcp-tui
             :command        (tnr-command r)
             :command-hash   (tnr-command-hash r)
             :evidence-ok-p  (tnr-notarized-p r)
             :artifact-count (if (tnr-notarized-p r) 2 0)
             :digest-key     (tnr-notarization-id r)
             :detail         (tnr-detail r)))
          (tbn-records tui-bundle)))

(defun harmonize-playwright-evidence (pw-bundle)
  "Convert PLAYWRIGHT-EVIDENCE-BUNDLE entries to harmonized scenario rows."
  (declare (type playwright-evidence-bundle pw-bundle)
           (optimize (safety 3)))
  (mapcar (lambda (e)
            (make-harmonized-scenario-row
             :scenario-id    (pbe-scenario-id e)
             :framework      :playwright
             :command        (peb-command pw-bundle)
             :command-hash   (pbe-command-hash e)
             :evidence-ok-p  (pbe-complete-p e)
             :artifact-count (if (pbe-complete-p e) 2 0)
             :digest-key     (format nil "~A-~A" (pbe-screenshot-hash e) (pbe-trace-hash e))
             :detail         (format nil "~A: ~A" (pbe-scenario-id e)
                                     (if (pbe-complete-p e) "complete" "missing"))))
          (peb-entries pw-bundle)))

(defun compile-harmonized-envelope (tui-bundle pw-bundle)
  "Compile a cross-framework harmonized evidence envelope."
  (declare (type tui-bundle-notarization tui-bundle)
           (type playwright-evidence-bundle pw-bundle)
           (optimize (safety 3)))
  (let* ((tui-rows (harmonize-tui-evidence tui-bundle))
         (pw-rows  (harmonize-playwright-evidence pw-bundle))
         (e3-pass  (every #'hsr-evidence-ok-p tui-rows))
         (e4-pass  (every #'hsr-evidence-ok-p pw-rows))
         (overall  (and e3-pass e4-pass)))
    (make-harmonized-evidence-envelope
     :envelope-id    (format nil "hee-~D" (get-universal-time))
     :epic3-rows     tui-rows
     :epic4-rows     pw-rows
     :epic3-pass-p   e3-pass
     :epic4-pass-p   e4-pass
     :overall-pass-p overall
     :timestamp      (get-universal-time)
     :detail         (format nil "e3=~A e4=~A overall=~A" e3-pass e4-pass overall))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %hsr->json (r)
  (declare (type harmonized-scenario-row r))
  (format nil "{\"scenario\":\"~A\",\"framework\":\"~A\",\"command_hash\":~D,\"evidence_ok\":~A,\"artifact_count\":~D}"
          (hsr-scenario-id r)
          (string-downcase (symbol-name (hsr-framework r)))
          (hsr-command-hash r)
          (if (hsr-evidence-ok-p r) "true" "false")
          (hsr-artifact-count r)))

(defun harmonized-evidence-envelope->json (env)
  (declare (type harmonized-evidence-envelope env))
  (with-output-to-string (out)
    (format out "{\"envelope_id\":\"~A\",\"epic3_pass\":~A,\"epic4_pass\":~A,\"overall_pass\":~A,\"timestamp\":~D,\"epic3_rows\":["
            (hee-envelope-id env)
            (if (hee-epic3-pass-p env) "true" "false")
            (if (hee-epic4-pass-p env) "true" "false")
            (if (hee-overall-pass-p env) "true" "false")
            (hee-timestamp env))
    (loop for r in (hee-epic3-rows env)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%hsr->json r) out)))
    (write-string "],\"epic4_rows\":[" out)
    (loop for r in (hee-epic4-rows env)
          for i from 0
          do (progn (when (> i 0) (write-char #\, out))
                    (write-string (%hsr->json r) out)))
    (format out "],\"detail\":\"~A\"}" (hee-detail env))))
