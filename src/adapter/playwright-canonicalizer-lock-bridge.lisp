;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-canonicalizer-lock-bridge.lisp — bt9-C
;;; Typed adapter wiring S1-S6 canonicalization/preflight into manifest lock gate.
;;; Bead: agent-orrery-8e2

(in-package #:orrery/adapter)

;;; ---------------------------------------------------------------------------
;;; Bridge record: typed DTO carrying canonicalized preflight into lock gate
;;; ---------------------------------------------------------------------------

(defstruct (canonicalizer-lock-input (:conc-name cli-))
  "Typed input assembled from playwright-preflight-verdict for lock gate."
  (scenario-id      ""    :type string)
  (command          ""    :type string)
  (command-fp       0     :type integer)
  (screenshot-path  ""    :type string)
  (trace-path       ""    :type string)
  (screenshot-ok-p  nil   :type boolean)
  (trace-ok-p       nil   :type boolean)
  (canonical-ok-p   nil   :type boolean))

(defstruct (lock-bridge-verdict (:conc-name lbv-))
  "Machine-checkable verdict emitted by the bridge for consumption by manifest lock."
  (pass-p           nil   :type boolean)
  (command          ""    :type string)
  (command-fp       0     :type integer)
  (artifact-root    ""    :type string)
  (complete-count   0     :type fixnum)
  (missing-scenarios nil  :type list)
  (detail           ""    :type string)
  (timestamp        0     :type integer))

;;; ---------------------------------------------------------------------------
;;; Declarations
;;; ---------------------------------------------------------------------------

(declaim
 (ftype (function (string string string)
                  (values canonicalizer-lock-input &optional))
        build-canonicalizer-lock-input)
 (ftype (function (playwright-preflight-verdict string)
                  (values lock-bridge-verdict &optional))
        preflight-verdict->lock-bridge-verdict)
 (ftype (function (string string)
                  (values lock-bridge-verdict &optional))
        run-canonicalizer-lock-bridge)
 (ftype (function (lock-bridge-verdict string)
                  (values evidence-manifest-lock &optional))
        bridge-verdict->manifest-lock)
 (ftype (function (lock-bridge-verdict)
                  (values string &optional))
        lock-bridge-verdict->json))

;;; ---------------------------------------------------------------------------
;;; Implementation
;;; ---------------------------------------------------------------------------

(defun build-canonicalizer-lock-input (scenario-id artifacts-root command)
  "Construct a canonicalizer-lock-input for one scenario-id from artifact root."
  (declare (type string scenario-id artifacts-root command))
  (let* ((shot-leaf (format nil "~A-screenshot.png" scenario-id))
         (trace-leaf (format nil "~A-trace.zip" scenario-id))
         (shot-path (merge-pathnames shot-leaf (pathname artifacts-root)))
         (trace-path (merge-pathnames trace-leaf (pathname artifacts-root)))
         (shot-ok (and (probe-file shot-path) t))
         (trace-ok (and (probe-file trace-path) t)))
    (make-canonicalizer-lock-input
     :scenario-id     scenario-id
     :command         command
     :command-fp      (sxhash command)
     :screenshot-path (namestring shot-path)
     :trace-path      (namestring trace-path)
     :screenshot-ok-p shot-ok
     :trace-ok-p      trace-ok
     :canonical-ok-p  (and shot-ok trace-ok))))

(defun preflight-verdict->lock-bridge-verdict (verdict artifacts-root)
  "Convert a playwright-preflight-verdict into a lock-bridge-verdict."
  (declare (type playwright-preflight-verdict verdict)
           (type string artifacts-root))
  (let* ((missing   (ppv-missing-scenarios verdict))
         (complete  (- (length *playwright-required-scenarios*) (length missing)))
         (pass-p    (and (ppv-pass-p verdict)
                         (null missing)
                         (ppv-command-ok-p verdict)
                         (ppv-canonical-pass-p verdict))))
    (make-lock-bridge-verdict
     :pass-p           pass-p
     :command          (ppv-detail verdict)   ; detail carries command string
     :command-fp       (sxhash (ppv-detail verdict))
     :artifact-root    artifacts-root
     :complete-count   (max 0 complete)
     :missing-scenarios missing
     :detail           (format nil "canonical_pass=~A command_ok=~A missing=~{~A~^,~}"
                                (ppv-canonical-pass-p verdict)
                                (ppv-command-ok-p verdict)
                                missing)
     :timestamp        (get-universal-time))))

(defun run-canonicalizer-lock-bridge (artifacts-root command)
  "End-to-end: run S1-S6 canonicalization preflight then produce lock-bridge-verdict."
  (declare (type string artifacts-root command))
  (let ((verdict (run-playwright-s1-s6-preflight artifacts-root command)))
    (preflight-verdict->lock-bridge-verdict verdict artifacts-root)))

(defun bridge-verdict->manifest-lock (bridge-verdict out-path)
  "Convert lock-bridge-verdict to an evidence-manifest-lock and write to out-path."
  (declare (type lock-bridge-verdict bridge-verdict)
           (type string out-path))
  (let ((lock (make-evidence-manifest-lock
               :epic              :epic4
               :command           (lbv-command bridge-verdict)
               :command-fingerprint (lbv-command-fp bridge-verdict)
               :artifact-root     (lbv-artifact-root bridge-verdict)
               :scenario-count    (length *playwright-required-scenarios*)
               :pass-p            (lbv-pass-p bridge-verdict)
               :timestamp         (lbv-timestamp bridge-verdict))))
    (ensure-directories-exist (pathname out-path))
    (with-open-file (s out-path :direction :output :if-exists :supersede)
      (write-string (evidence-manifest-lock->json lock) s))
    lock))

(defun lock-bridge-verdict->json (verdict)
  "Serialize lock-bridge-verdict to JSON string."
  (declare (type lock-bridge-verdict verdict))
  (format nil
   "{\"pass\":~A,\"command_fp\":~D,\"artifact_root\":\"~A\",\"complete_count\":~D,~
    \"missing\":~A,\"detail\":\"~A\",\"timestamp\":~D}"
   (if (lbv-pass-p verdict) "true" "false")
   (lbv-command-fp verdict)
   (lbv-artifact-root verdict)
   (lbv-complete-count verdict)
   (if (lbv-missing-scenarios verdict)
       (format nil "[~{\"~A\"~^,~}]" (lbv-missing-scenarios verdict))
       "[]")
   (lbv-detail verdict)
   (lbv-timestamp verdict)))
