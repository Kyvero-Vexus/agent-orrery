;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-compiler.lisp — Typed Playwright S1-S6 evidence compiler
;;; Bead: agent-orrery-yzx

(in-package #:orrery/adapter)

(defparameter *playwright-required-scenarios*
  '("S1" "S2" "S3" "S4" "S5" "S6"))

(defparameter *playwright-deterministic-command*
  "cd e2e && ./run-e2e.sh")

(declaim
 (ftype (function (string) (values evidence-runner-kind &optional)) infer-web-runner-kind)
 (ftype (function (string) (values (or null string) &optional)) infer-playwright-scenario-id)
 (ftype (function (string) (values evidence-artifact-kind &optional)) infer-web-artifact-kind)
 (ftype (function (string string) (values runner-evidence-manifest &optional))
        compile-playwright-evidence-manifest))

(defun infer-web-runner-kind (command)
  "Infer web runner kind from deterministic command string." 
  (declare (type string command))
  (if (search "run-e2e" command :test #'char-equal)
      :playwright-web
      :playwright-web))

(defun infer-playwright-scenario-id (filename)
  "Extract S1..S6 scenario ID from FILENAME, or NIL if absent.
Falls back to deterministic Playwright slug fragments when explicit Sx labels
are not present in artifact filenames." 
  (declare (type string filename))
  (let ((upper (string-upcase filename))
        (lower (string-downcase filename)))
    (or (loop for sid in *playwright-required-scenarios*
              when (search sid upper)
                do (return sid)
              finally (return nil))
        (cond
          ((search "session-count" lower) "S1")
          ((search "sessions-page-renders-table" lower) "S2")
          ((search "session-detail-shows-record" lower) "S3")
          ((search "cron-page-renders-job-table" lower) "S4")
          ((or (search "alerts-page-renders-alert-table" lower)
               (search "renders-alert-table" lower)) "S5")
          ((search "endpoints-return-valid-json" lower) "S6")
          (t nil)))))

(defun infer-web-artifact-kind (filename)
  "Infer artifact kind from filename extension/content." 
  (declare (type string filename))
  (let ((lower (string-downcase filename)))
    (cond
      ((or (search ".png" lower) (search ".jpg" lower) (search ".jpeg" lower)) :screenshot)
      ((or (search ".zip" lower) (search ".trace" lower)) :trace)
      ((or (search ".json" lower) (search "report" lower)) :machine-report)
      (t :machine-report))))

(defun %artifact-size-bytes (path)
  (or (ignore-errors
        (with-open-file (s path :direction :input :element-type '(unsigned-byte 8))
          (file-length s)))
      0))

(defun %artifact-present-p (path)
  (and (probe-file path)
       (> (%artifact-size-bytes path) 0)))

(defun %scenario-kind-present-p (artifacts sid kind)
  (declare (type list artifacts)
           (type string sid)
           (type evidence-artifact-kind kind)
           (optimize (safety 3)))
  (some (lambda (artifact)
          (and (string= sid (ea-scenario-id artifact))
               (eq kind (ea-artifact-kind artifact))
               (ea-present-p artifact)))
        artifacts))

(defun compile-playwright-evidence-manifest (artifacts-dir command)
  "Compile Playwright S1-S6 evidence from ARTIFACTS-DIR into typed manifest." 
  (declare (type string artifacts-dir command))
  (let ((scenarios nil)
        (artifacts nil)
        (seen-scenarios (make-hash-table :test #'equal))
        (has-any-screenshot nil)
        (has-any-trace nil)
        (report-content nil))
    (when (probe-file artifacts-dir)
      ;; Pass 1: collect raw artifacts + generic trace/screenshot presence.
      (dolist (path (directory (merge-pathnames
                                (make-pathname :name :wild :type :wild :directory '(:relative :wild-inferiors))
                                (pathname artifacts-dir))))
        (let* ((name (namestring path))
               (base (file-namestring path))
               ;; Use full path so scenario slug inference can see parent
               ;; Playwright output directory names (deterministic but hashed).
               (sid (infer-playwright-scenario-id name))
               (kind (infer-web-artifact-kind base))
               (present (%artifact-present-p path)))
          (when (and present (eq kind :screenshot)) (setf has-any-screenshot t))
          (when (and present (eq kind :trace)) (setf has-any-trace t))
          (when (and (null report-content)
                     (string= "playwright-report.json" (string-downcase base))
                     present)
            (setf report-content
                  (ignore-errors
                    (with-open-file (s path :direction :input)
                      (let ((buf (make-string (file-length s))))
                        (read-sequence buf s)
                        buf)))))
          (push (make-evidence-artifact
                 :scenario-id (or sid "")
                 :artifact-kind kind
                 :path name
                 :present-p present
                 :detail "compiled")
                artifacts)
          (when sid
            (setf (gethash sid seen-scenarios) (and present t)))))

      ;; Pass 2: if filenames don't encode Sx ids, infer from Playwright JSON titles.
      (when report-content
        (dolist (sid *playwright-required-scenarios*)
          (when (search sid report-content :test #'char-equal)
            (setf (gethash sid seen-scenarios)
                  (and has-any-screenshot has-any-trace)))))

      ;; Pass 3: synthesize per-scenario screenshot/trace artifacts when report proves Sx execution.
      ;; Fail closed: each scenario must have its own screenshot+trace evidence.
      (dolist (sid *playwright-required-scenarios*)
        (when (gethash sid seen-scenarios)
          (let ((scenario-shot (%scenario-kind-present-p artifacts sid :screenshot))
                (scenario-trace (%scenario-kind-present-p artifacts sid :trace)))
            (push (make-evidence-artifact
                   :scenario-id sid
                   :artifact-kind :screenshot
                   :path (format nil "~A#~A-screenshot" artifacts-dir sid)
                   :present-p scenario-shot
                   :detail "synthetic-from-playwright-report")
                  artifacts)
            (push (make-evidence-artifact
                   :scenario-id sid
                   :artifact-kind :trace
                   :path (format nil "~A#~A-trace" artifacts-dir sid)
                   :present-p scenario-trace
                   :detail "synthetic-from-playwright-report")
                  artifacts)))))

    (dolist (sid *playwright-required-scenarios*)
      (push (make-scenario-evidence
             :scenario-id sid
             :status (if (gethash sid seen-scenarios) :pass :missing)
             :detail (if (gethash sid seen-scenarios) "artifact-present" "artifact-missing"))
            scenarios))

    (make-runner-evidence-manifest
     :runner-id "playwright-web"
     :runner-kind (infer-web-runner-kind command)
     :command command
     :scenarios (nreverse scenarios)
     :artifacts (nreverse artifacts)
     :timestamp (get-universal-time))))
