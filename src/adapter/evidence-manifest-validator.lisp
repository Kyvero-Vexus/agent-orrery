;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; e2e-manifest-validator.lisp — Typed E2E evidence manifest validator
;;;
;;; Validates that E2E evidence artifacts (screenshots, traces, reports)
;;; exist and meet the policy contracts for Web (S1-S6) and TUI (T1-T6).
;;; Used as a CI hook to fail builds on missing coverage.
;;;
;;; Beads: agent-orrery-qo5, agent-orrery-oo1

(in-package #:orrery/adapter)

;;; ============================================================
;;; Evidence Manifest Types
;;; ============================================================

(deftype evidence-kind ()
  "Kind of E2E evidence artifact."
  '(member :screenshot :trace :report :transcript :asciicast))

(deftype evidence-suite ()
  "Which E2E suite this evidence belongs to."
  '(member :web-playwright :tui-mcp-driver))

(defstruct (manifest-artifact
            (:constructor make-manifest-artifact)
            (:copier nil))
  "A single evidence artifact descriptor."
  (scenario-id  ""     :type string    :read-only t)
  (kind         :screenshot :type evidence-kind :read-only t)
  (path         ""     :type string    :read-only t)
  (exists-p     nil    :type boolean)
  (size-bytes   0      :type (integer 0 *)))

(defstruct (e2e-manifest
            (:constructor make-e2e-manifest)
            (:copier nil))
  "A complete evidence manifest for a suite."
  (suite        :web-playwright :type evidence-suite :read-only t)
  (artifacts    nil    :type list)
  (scenarios-required nil :type list :read-only t)
  (deterministic-command "" :type string :read-only t)
  (valid-p      nil    :type boolean)
  (missing      nil    :type list)
  (errors       nil    :type list))

;;; ============================================================
;;; Policy Constants
;;; ============================================================

(defparameter *web-required-scenarios*
  '("S1" "S2" "S3" "S4" "S5" "S6")
  "Required Playwright web E2E scenarios.")

(defparameter *tui-required-scenarios*
  '("T1" "T2" "T3" "T4" "T5" "T6" "T7" "T8")
  "Required mcp-tui-driver TUI E2E scenarios.")

(defparameter *web-deterministic-command*
  "cd e2e && bash run-e2e.sh"
  "Deterministic command to reproduce Web E2E evidence.")

(defparameter *tui-deterministic-command*
  "make e2e-tui"
  "Deterministic command to reproduce TUI E2E evidence.")

(defparameter *web-required-artifacts-per-scenario*
  '(:screenshot :trace)
  "Each web scenario must produce at least these artifact kinds.")

(defparameter *tui-required-artifacts-per-scenario*
  '(:screenshot :transcript)
  "Each TUI scenario must produce at least these artifact kinds.")

(defparameter *suite-required-artifacts*
  '((:web-playwright . nil)
    (:tui-mcp-driver . (:report :asciicast)))
  "Suite-level artifact requirements independent of per-scenario files.")

;;; ============================================================
;;; Artifact Discovery
;;; ============================================================

(declaim (ftype (function (string string) list) discover-artifacts-in-dir)
         (ftype (function (evidence-suite string) list) discover-suite-artifacts)
         (ftype (function (string) string) normalize-artifact-path)
         (ftype (function (list) list) normalize-manifest-artifacts)
         (ftype (function (e2e-manifest) e2e-manifest) normalize-e2e-manifest)
         (ftype (function (evidence-suite string) e2e-manifest) validate-and-normalize-e2e-manifest)
         (ftype (function (string) boolean) epic3-t1-t6-evidence-ok-p))

(defun %infer-evidence-kind (lower-name)
  (cond
    ((or (search ".png" lower-name)
         (search ".jpg" lower-name)
         (search ".jpeg" lower-name))
     :screenshot)
    ((or (search ".zip" lower-name)
         (search ".trace" lower-name))
     :trace)
    ((or (search ".json" lower-name)
         (search "report" lower-name))
     :report)
    ((or (search ".txt" lower-name)
         (search "transcript" lower-name))
     :transcript)
    ((search ".cast" lower-name)
     :asciicast)
    (t nil)))

(defun discover-artifacts-in-dir (directory scenario-id)
  "Scan DIRECTORY for artifacts matching SCENARIO-ID. Returns list of manifest-artifact."
  (declare (type string directory scenario-id))
  (let ((artifacts nil)
        (pattern (string-downcase scenario-id)))
    (when (probe-file directory)
      (dolist (path (directory (merge-pathnames
                                (make-pathname :name :wild :type :wild)
                                (pathname directory))))
        (let* ((name (namestring path))
               (lower-name (string-downcase (file-namestring path))))
          (when (search pattern lower-name)
            (let ((kind (%infer-evidence-kind lower-name)))
              (when kind
                (push (make-manifest-artifact
                       :scenario-id scenario-id
                       :kind kind
                       :path name
                       :exists-p (not (null (probe-file path)))
                       :size-bytes (or (ignore-errors
                                         (with-open-file (s path :element-type '(unsigned-byte 8))
                                           (file-length s)))
                                       0))
                      artifacts)))))))
    (nreverse artifacts)))

(defun discover-suite-artifacts (suite directory)
  "Discover suite-level artifacts not tied to a specific scenario id."
  (declare (type evidence-suite suite)
           (type string directory))
  (let ((required-kinds (or (cdr (assoc suite *suite-required-artifacts*)) '()))
        (artifacts nil))
    (when (probe-file directory)
      (dolist (path (directory (merge-pathnames
                                (make-pathname :name :wild :type :wild)
                                (pathname directory))))
        (let* ((name (namestring path))
               (lower-name (string-downcase (file-namestring path)))
               (kind (%infer-evidence-kind lower-name)))
          (when (and kind (member kind required-kinds :test #'eq))
            (push (make-manifest-artifact
                   :scenario-id "SUITE"
                   :kind kind
                   :path name
                   :exists-p (not (null (probe-file path)))
                   :size-bytes (or (ignore-errors
                                     (with-open-file (s path :element-type '(unsigned-byte 8))
                                       (file-length s)))
                                   0))
                  artifacts)))))
    (nreverse artifacts)))

;;; ============================================================
;;; Manifest Normalization
;;; ============================================================

(defun normalize-artifact-path (path)
  "Normalize artifact PATH for deterministic manifest output."
  (declare (type string path))
  (let* ((pn (pathname path))
         (name (or (pathname-name pn) ""))
         (type (or (pathname-type pn) "")))
    (string-downcase
     (if (plusp (length type))
         (format nil "~A.~A" name type)
         name))))

(defun %artifact-kind-rank (kind)
  (declare (type evidence-kind kind))
  (position kind '(:screenshot :trace :report :transcript :asciicast) :test #'eq))

(defun normalize-manifest-artifacts (artifacts)
  "Normalize, deduplicate, and sort manifest artifacts.
Dedup key: (scenario-id, kind), keep the largest existing artifact."
  (declare (type list artifacts))
  (let ((table (make-hash-table :test #'equal)))
    (dolist (a artifacts)
      (let* ((sid (string-upcase (manifest-artifact-scenario-id a)))
             (kind (manifest-artifact-kind a))
             (key (format nil "~A|~A" sid kind))
             (normalized (make-manifest-artifact
                          :scenario-id sid
                          :kind kind
                          :path (normalize-artifact-path (manifest-artifact-path a))
                          :exists-p (manifest-artifact-exists-p a)
                          :size-bytes (manifest-artifact-size-bytes a)))
             (current (gethash key table)))
        (when (or (null current)
                  (< (manifest-artifact-size-bytes current)
                     (manifest-artifact-size-bytes normalized)))
          (setf (gethash key table) normalized))))
    (labels ((artifact< (a b)
               (let* ((sa (manifest-artifact-scenario-id a))
                      (sb (manifest-artifact-scenario-id b))
                      (ka (or (%artifact-kind-rank (manifest-artifact-kind a)) 99))
                      (kb (or (%artifact-kind-rank (manifest-artifact-kind b)) 99)))
                 (cond
                   ((string< sa sb) t)
                   ((string> sa sb) nil)
                   ((< ka kb) t)
                   ((> ka kb) nil)
                   (t (string< (manifest-artifact-path a)
                               (manifest-artifact-path b)))))))
      (sort (loop for v being the hash-values of table collect v)
            #'artifact<))))

(defun normalize-e2e-manifest (manifest)
  "Normalize manifest for deterministic machine-checkable output."
  (declare (type e2e-manifest manifest))
  (let* ((artifacts (normalize-manifest-artifacts (e2e-manifest-artifacts manifest)))
         (missing (sort (remove-duplicates (copy-list (e2e-manifest-missing manifest)) :test #'string=)
                        #'string<))
         (errors (sort (remove-duplicates (copy-list (e2e-manifest-errors manifest)) :test #'string=)
                       #'string<))
         (scenarios (sort (copy-list (e2e-manifest-scenarios-required manifest)) #'string<)))
    (make-e2e-manifest
     :suite (e2e-manifest-suite manifest)
     :artifacts artifacts
     :scenarios-required scenarios
     :deterministic-command (e2e-manifest-deterministic-command manifest)
     :valid-p (and (null missing) (null errors))
     :missing missing
     :errors errors)))

;;; ============================================================
;;; Manifest Validation
;;; ============================================================

(declaim (ftype (function (evidence-suite string) e2e-manifest) validate-e2e-manifest))
(defun validate-e2e-manifest (suite artifacts-directory)
  "Build and validate an evidence manifest for SUITE from ARTIFACTS-DIRECTORY.
Returns an e2e-manifest struct with valid-p set."
  (declare (type evidence-suite suite)
           (type string artifacts-directory))
  (let* ((required-scenarios (ecase suite
                               (:web-playwright *web-required-scenarios*)
                               (:tui-mcp-driver *tui-required-scenarios*)))
         (det-command (ecase suite
                        (:web-playwright *web-deterministic-command*)
                        (:tui-mcp-driver *tui-deterministic-command*)))
         (required-kinds (ecase suite
                           (:web-playwright *web-required-artifacts-per-scenario*)
                           (:tui-mcp-driver *tui-required-artifacts-per-scenario*)))
         (suite-required-kinds (or (cdr (assoc suite *suite-required-artifacts*)) '()))
         (all-artifacts nil)
         (missing nil)
         (errors nil))
    ;; Discover artifacts per scenario
    (dolist (scenario required-scenarios)
      (let ((found (discover-artifacts-in-dir artifacts-directory scenario)))
        (setf all-artifacts (append all-artifacts found))
        ;; Check each required kind
        (dolist (kind required-kinds)
          (unless (find kind found :key #'manifest-artifact-kind)
            (push (format nil "~A: missing ~A artifact" scenario kind) missing)))))
    ;; Suite-level required artifacts (e.g., report + asciicast for TUI)
    (let ((suite-artifacts (discover-suite-artifacts suite artifacts-directory)))
      (setf all-artifacts (append all-artifacts suite-artifacts))
      (dolist (kind suite-required-kinds)
        (unless (find kind suite-artifacts :key #'manifest-artifact-kind)
          (push (format nil "SUITE: missing ~A artifact" kind) missing))))

    ;; Check for zero-byte artifacts
    (dolist (art all-artifacts)
      (when (and (manifest-artifact-exists-p art)
                 (zerop (manifest-artifact-size-bytes art)))
        (push (format nil "~A: zero-byte ~A at ~A"
                       (manifest-artifact-scenario-id art)
                       (manifest-artifact-kind art)
                       (manifest-artifact-path art))
              errors)))
    ;; Build manifest
    (make-e2e-manifest
     :suite suite
     :artifacts all-artifacts
     :scenarios-required required-scenarios
     :deterministic-command det-command
     :valid-p (and (null missing) (null errors))
     :missing (nreverse missing)
     :errors (nreverse errors))))

(defun validate-and-normalize-e2e-manifest (suite artifacts-directory)
  "Validate SUITE manifest from ARTIFACTS-DIRECTORY and normalize deterministically."
  (declare (type evidence-suite suite)
           (type string artifacts-directory))
  (normalize-e2e-manifest
   (validate-e2e-manifest suite artifacts-directory)))

(defun epic3-t1-t6-evidence-ok-p (artifacts-directory)
  "Hard guard for Epic 3 closure: requires T1-T6 evidence + suite artifacts.
Returns T only when deterministic command metadata and required artifacts are valid." 
  (declare (type string artifacts-directory))
  (let* ((manifest (validate-and-normalize-e2e-manifest :tui-mcp-driver artifacts-directory))
         (required-ids '("T1" "T2" "T3" "T4" "T5" "T6"))
         (artifacts (e2e-manifest-artifacts manifest))
         (cmd (e2e-manifest-deterministic-command manifest))
         (command-ok (or (string= cmd "make e2e-tui")
                         (string= cmd "make e2e-tui-t1-t6")))
         (scenario-ok
           (every (lambda (sid)
                    (let ((for-sid (remove-if-not
                                    (lambda (a) (string= sid (manifest-artifact-scenario-id a)))
                                    artifacts)))
                      (and (not (null (find :screenshot for-sid :key #'manifest-artifact-kind)))
                           (not (null (find :transcript for-sid :key #'manifest-artifact-kind))))))
                  required-ids))
         (suite-ok
           (let ((suite-items (remove-if-not
                               (lambda (a) (string= "SUITE" (manifest-artifact-scenario-id a)))
                               artifacts)))
             (and (not (null (find :report suite-items :key #'manifest-artifact-kind)))
                  (not (null (find :asciicast suite-items :key #'manifest-artifact-kind)))))))
    (and command-ok scenario-ok suite-ok)))

;;; ============================================================
;;; CI Hook
;;; ============================================================

(declaim (ftype (function (e2e-manifest &optional stream) boolean) report-manifest-validity))
(defun report-manifest-validity (manifest &optional (stream *standard-output*))
  "Print a validity report for MANIFEST. Returns VALID-P."
  (declare (type e2e-manifest manifest))
  (format stream "~&=== Evidence Manifest Report (~A) ===~%"
          (e2e-manifest-suite manifest))
  (format stream "Command: ~A~%" (e2e-manifest-deterministic-command manifest))
  (format stream "Required scenarios: ~{~A~^, ~}~%"
          (e2e-manifest-scenarios-required manifest))
  (format stream "Artifacts found: ~D~%" (length (e2e-manifest-artifacts manifest)))
  (if (e2e-manifest-valid-p manifest)
      (format stream "~&STATUS: PASS~%")
      (progn
        (format stream "~&STATUS: FAIL~%")
        (when (e2e-manifest-missing manifest)
          (format stream "~&Missing:~%")
          (dolist (m (e2e-manifest-missing manifest))
            (format stream "  - ~A~%" m)))
        (when (e2e-manifest-errors manifest)
          (format stream "~&Errors:~%")
          (dolist (e (e2e-manifest-errors manifest))
            (format stream "  - ~A~%" e)))))
  (e2e-manifest-valid-p manifest))

(declaim (ftype (function () (values boolean boolean)) ci-check-all-evidence))
(defun ci-check-all-evidence ()
  "CI entrypoint: validate both web and TUI evidence.
Returns (VALUES web-ok tui-ok)."
  (let* ((web-manifest (validate-and-normalize-e2e-manifest
                        :web-playwright
                        "test-results/e2e-report/"))
         (tui-manifest (validate-and-normalize-e2e-manifest
                        :tui-mcp-driver
                        "test-results/tui-artifacts/"))
         (web-ok (report-manifest-validity web-manifest))
         (tui-ok (report-manifest-validity tui-manifest)))
    (values web-ok tui-ok)))
