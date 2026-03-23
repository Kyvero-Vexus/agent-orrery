;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-scenario-manifest.lisp — typed S1-S6 scenario manifest ADTs + Playwright artifact schema
;;; Bead: agent-orrery-2w69

(in-package #:orrery/adapter)

;;; ── Artifact descriptor ──────────────────────────────────────────────────────

(defstruct (playwright-artifact-descriptor (:conc-name pad-))
  "Typed descriptor for one Playwright scenario artifact (screenshot or trace)."
  (scenario-id  ""         :type string)
  (kind         :screenshot :type (member :screenshot :trace))
  (path         ""          :type string)
  (present-p    nil         :type boolean)
  (digest       ""          :type string))

;;; ── Scenario manifest entry ──────────────────────────────────────────────────

(defstruct (playwright-scenario-manifest-entry (:conc-name psme-))
  "Typed manifest entry for one Playwright scenario (S1..S6)."
  (scenario-id    ""    :type string)
  (command        ""    :type string)
  (command-hash   0     :type integer)
  (screenshot     nil   :type (or null playwright-artifact-descriptor))
  (trace          nil   :type (or null playwright-artifact-descriptor))
  (complete-p     nil   :type boolean)
  (detail         ""    :type string))

;;; ── Scenario manifest ────────────────────────────────────────────────────────

(defstruct (playwright-scenario-manifest (:conc-name psm-))
  "Typed S1-S6 Playwright scenario manifest with command fingerprint and coverage."
  (run-id         ""    :type string)
  (command        ""    :type string)
  (command-hash   0     :type integer)
  (entries        nil   :type list)    ; list of playwright-scenario-manifest-entry
  (total-count    0     :type integer)
  (complete-count 0     :type integer)
  (missing-count  0     :type integer)
  (pass-p         nil   :type boolean)
  (timestamp      0     :type integer))

;;; ── Declaim ──────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string string evidence-artifact-kind)
                  (values playwright-artifact-descriptor &optional))
        build-playwright-artifact-descriptor)
 (ftype (function (string string)
                  (values playwright-scenario-manifest-entry &optional))
        build-playwright-scenario-manifest-entry)
 (ftype (function (string string)
                  (values playwright-scenario-manifest &optional))
        compile-playwright-scenario-manifest)
 (ftype (function (playwright-scenario-manifest) (values string &optional))
        playwright-scenario-manifest->json))

;;; ── Builders ─────────────────────────────────────────────────────────────────

(defun build-playwright-artifact-descriptor (artifact-root scenario-id kind)
  (declare (type string artifact-root scenario-id)
           (type evidence-artifact-kind kind))
  (let* ((manifest (compile-playwright-evidence-manifest artifact-root ""))
         (path (find-web-scenario-artifact-path manifest scenario-id kind))
         (present (and (plusp (length path)) (probe-file path)))
         (digest (if present (%hash-text-file path) "")))
    (make-playwright-artifact-descriptor
     :scenario-id scenario-id
     :kind (if (eq kind :screenshot) :screenshot :trace)
     :path path
     :present-p (not (null present))
     :digest digest)))

(defun build-playwright-scenario-manifest-entry (artifact-root scenario-id)
  (declare (type string artifact-root scenario-id))
  (let* ((cmd *playwright-canonical-command*)
         (h   *playwright-canonical-command-hash*)
         (scr (build-playwright-artifact-descriptor artifact-root scenario-id :screenshot))
         (trc (build-playwright-artifact-descriptor artifact-root scenario-id :trace))
         (ok  (and (pad-present-p scr) (pad-present-p trc))))
    (make-playwright-scenario-manifest-entry
     :scenario-id  scenario-id
     :command      cmd
     :command-hash h
     :screenshot   scr
     :trace        trc
     :complete-p   ok
     :detail       (if ok
                       (format nil "~A: complete" scenario-id)
                       (format nil "~A: missing ~{~A~^,~}"
                               scenario-id
                               (append (unless (pad-present-p scr) '("screenshot"))
                                       (unless (pad-present-p trc) '("trace"))))))))

(defun compile-playwright-scenario-manifest (artifact-root command)
  "Build a typed S1-S6 scenario manifest from ARTIFACT-ROOT using COMMAND."
  (declare (type string artifact-root command))
  (let* ((entries (mapcar (lambda (sid)
                            (build-playwright-scenario-manifest-entry artifact-root sid))
                          *playwright-required-scenarios*))
         (complete (count-if #'psme-complete-p entries))
         (missing  (- (length entries) complete))
         (pass     (zerop missing)))
    (make-playwright-scenario-manifest
     :run-id         (format nil "psm-~D" (get-universal-time))
     :command        command
     :command-hash   (command-fingerprint command)
     :entries        entries
     :total-count    (length entries)
     :complete-count complete
     :missing-count  missing
     :pass-p         pass
     :timestamp      (get-universal-time))))

;;; ── JSON ─────────────────────────────────────────────────────────────────────

(defun %pad->json (d)
  (declare (type playwright-artifact-descriptor d))
  (format nil "{\"scenario\":\"~A\",\"kind\":\"~A\",\"present\":~A,\"digest\":\"~A\"}"
          (pad-scenario-id d)
          (string-downcase (symbol-name (pad-kind d)))
          (if (pad-present-p d) "true" "false")
          (pad-digest d)))

(defun %psme->json (e)
  (declare (type playwright-scenario-manifest-entry e))
  (with-output-to-string (out)
    (format out
            "{\"scenario\":\"~A\",\"complete\":~A,\"command_hash\":~D,\"screenshot\":~A,\"trace\":~A,\"detail\":\"~A\"}"
            (psme-scenario-id e)
            (if (psme-complete-p e) "true" "false")
            (psme-command-hash e)
            (if (psme-screenshot e) (%pad->json (psme-screenshot e)) "null")
            (if (psme-trace e) (%pad->json (psme-trace e)) "null")
            (psme-detail e))))

(defun playwright-scenario-manifest->json (manifest)
  (declare (type playwright-scenario-manifest manifest))
  (with-output-to-string (out)
    (format out
            "{\"run_id\":\"~A\",\"command_hash\":~D,\"total\":~D,\"complete\":~D,\"missing\":~D,\"pass\":~A,\"timestamp\":~D,\"entries\":["
            (psm-run-id manifest)
            (psm-command-hash manifest)
            (psm-total-count manifest)
            (psm-complete-count manifest)
            (psm-missing-count manifest)
            (if (psm-pass-p manifest) "true" "false")
            (psm-timestamp manifest))
    (loop for e in (psm-entries manifest)
          for i from 0
          do (progn
               (when (> i 0) (write-char #\, out))
               (write-string (%psme->json e) out)))
    (write-string "]}" out)))
