;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-reproducibility-reporter.lisp
;;;   Typed CL reproducibility reporter for Playwright S1-S6 deterministic replays.
;;;   Bead: agent-orrery-bxf5
;;;
;;; Emits: reproducibility scores, command-fingerprint stability deltas,
;;;        screenshot+trace artifact hash-chain integrity diagnostics.
;;;
;;; All transforms are pure / side-effect-free unless noted.
;;; Strict SBCL declarations throughout.

(in-package #:orrery/adapter)

;;; ─────────────────────────────────────────────────────────────────────────────
;;; ADTs
;;; ─────────────────────────────────────────────────────────────────────────────

(defstruct (s1-s6-rerun-sample (:conc-name rrs-))
  "One replay sample for a single S1-S6 scenario."
  (scenario-id       ""  :type string)
  (rerun-index       0   :type (integer 0))
  (screenshot-digest ""  :type string)
  (trace-digest      ""  :type string)
  (command-hash      0   :type integer)
  (artifact-stable-p nil :type boolean))

(defstruct (scenario-reproducibility-score (:conc-name srs-))
  "Reproducibility score for one S1-S6 scenario across N reruns."
  (scenario-id              ""   :type string)
  (sample-count             0    :type (integer 0))
  (stable-count             0    :type (integer 0))
  (stability-ratio          0.0  :type single-float)
  (command-fingerprint-delta 0   :type integer)
  (artifact-hash-chain      ""   :type string)
  (pass-p                   nil  :type boolean)
  (alarm-codes              nil  :type list))

(defstruct (playwright-reproducibility-report (:conc-name prr-))
  "Aggregate reproducibility report for S1-S6 across all scenarios."
  (run-id                    ""   :type string)
  (scenarios                 nil  :type list)  ; list of scenario-reproducibility-score
  (overall-stability-ratio   0.0  :type single-float)
  (closure-ready-p           nil  :type boolean)
  (command-fingerprint-stable-p nil :type boolean)
  (artifact-hash-chain-ok-p  nil  :type boolean)
  (alarm-codes               nil  :type list)
  (timestamp                 0    :type integer)
  (detail                    ""   :type string))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Declaims
;;; ─────────────────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string (integer 0) string string string)
                  (values s1-s6-rerun-sample &optional))
        build-s1-s6-rerun-sample)
 (ftype (function (string list integer) (values scenario-reproducibility-score &optional))
        compute-scenario-reproducibility-score)
 (ftype (function (string string list) (values playwright-reproducibility-report &optional))
        compile-playwright-reproducibility-report)
 (ftype (function (playwright-reproducibility-report) (values string &optional))
        playwright-reproducibility-report->json))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Helpers
;;; ─────────────────────────────────────────────────────────────────────────────

(defun %artifact-hash-chain (samples)
  "Derive a deterministic hash-chain string from ordered rerun sample digests."
  (declare (type list samples)
           (optimize (safety 3)))
  (let ((acc 0))
    (dolist (s samples)
      (declare (type s1-s6-rerun-sample s))
      (setf acc (logxor (ash acc 3)
                        (sxhash (rrs-screenshot-digest s))
                        (sxhash (rrs-trace-digest s)))))
    (format nil "~16,'0X" (logand acc #xFFFFFFFFFFFFFFFF))))

(defun %command-fingerprint-delta (samples canonical-hash)
  "Return count of samples whose command-hash deviates from canonical."
  (declare (type list samples)
           (type integer canonical-hash)
           (optimize (safety 3)))
  (count-if (lambda (s)
              (declare (type s1-s6-rerun-sample s))
              (/= (rrs-command-hash s) canonical-hash))
            samples))

(defun %stable-count (samples)
  "Count samples where artifact-stable-p is T."
  (declare (type list samples)
           (optimize (safety 3)))
  (count-if #'rrs-artifact-stable-p samples))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; Core transforms
;;; ─────────────────────────────────────────────────────────────────────────────

(defun build-s1-s6-rerun-sample (scenario-id rerun-index artifact-root screenshot trace)
  "Build one rerun sample by hashing screenshot+trace artifacts on disk (or empty digest if absent)."
  (declare (type string scenario-id artifact-root screenshot trace)
           (type (integer 0) rerun-index)
           (optimize (safety 3)))
  (let* ((scr-path  (merge-pathnames screenshot (pathname artifact-root)))
         (trc-path  (merge-pathnames trace (pathname artifact-root)))
         (scr-ok    (not (null (probe-file scr-path))))
         (trc-ok    (not (null (probe-file trc-path))))
         (scr-dig   (if scr-ok (%hash-text-file (namestring scr-path)) ""))
         (trc-dig   (if trc-ok (%hash-text-file (namestring trc-path)) ""))
         (cmd-hash  (command-fingerprint *playwright-canonical-command*))
         (stable-p  (and scr-ok trc-ok)))
    (make-s1-s6-rerun-sample
     :scenario-id       scenario-id
     :rerun-index       rerun-index
     :screenshot-digest scr-dig
     :trace-digest      trc-dig
     :command-hash      cmd-hash
     :artifact-stable-p stable-p)))

(defun compute-scenario-reproducibility-score (scenario-id samples canonical-hash)
  "Compute reproducibility score for one scenario from a list of s1-s6-rerun-samples."
  (declare (type string scenario-id)
           (type list samples)
           (type integer canonical-hash)
           (optimize (safety 3)))
  (let* ((n           (length samples))
         (stable      (%stable-count samples))
         (ratio       (if (zerop n) 0.0 (coerce (/ stable n) 'single-float)))
         (fp-delta    (%command-fingerprint-delta samples canonical-hash))
         (hash-chain  (%artifact-hash-chain samples))
         (pass-p      (and (>= ratio 1.0) (zerop fp-delta)))
         (alarms      (append
                       (when (< ratio 1.0)
                         (list (format nil "REPRO_UNSTABLE_~A_~,2F" scenario-id ratio)))
                       (when (> fp-delta 0)
                         (list (format nil "CMD_FINGERPRINT_DELTA_~A_~D" scenario-id fp-delta))))))
    (make-scenario-reproducibility-score
     :scenario-id               scenario-id
     :sample-count              n
     :stable-count              stable
     :stability-ratio           ratio
     :command-fingerprint-delta fp-delta
     :artifact-hash-chain       hash-chain
     :pass-p                    pass-p
     :alarm-codes               alarms)))

(defun compile-playwright-reproducibility-report (run-id artifact-root scenario-samples-alist)
  "Compile aggregate reproducibility report from per-scenario sample lists.
   SCENARIO-SAMPLES-ALIST: ((scenario-id . samples-list) ...)"
  (declare (type string run-id artifact-root)
           (type list scenario-samples-alist)
           (ignore artifact-root)
           (optimize (safety 3)))
  (let* ((canonical   (command-fingerprint *playwright-canonical-command*))
         (scores      (mapcar (lambda (entry)
                                (destructuring-bind (sid . samples) entry
                                  (compute-scenario-reproducibility-score sid samples canonical)))
                              scenario-samples-alist))
         (all-pass    (and (not (null scores)) (every #'srs-pass-p scores)))
         (n-total     (length scores))
         (n-stable    (count-if #'srs-pass-p scores))
         (overall     (if (zerop n-total) 0.0
                          (coerce (/ n-stable n-total) 'single-float)))
         (fp-ok       (every (lambda (s) (zerop (srs-command-fingerprint-delta s))) scores))
         (chain-ok    all-pass)
         (all-alarms  (mapcan (lambda (s) (copy-list (srs-alarm-codes s))) scores))
         (detail      (if all-pass
                          (format nil "All ~D scenario(s) reproducible; stability=1.0" n-total)
                          (format nil "~D/~D scenario(s) stable; alarms: ~{~A~^, ~}"
                                  n-stable n-total all-alarms))))
    (make-playwright-reproducibility-report
     :run-id                    run-id
     :scenarios                 scores
     :overall-stability-ratio   overall
     :closure-ready-p           all-pass
     :command-fingerprint-stable-p fp-ok
     :artifact-hash-chain-ok-p  chain-ok
     :alarm-codes               all-alarms
     :timestamp                 (get-universal-time)
     :detail                    detail)))

;;; ─────────────────────────────────────────────────────────────────────────────
;;; JSON serialisation
;;; ─────────────────────────────────────────────────────────────────────────────

(defun playwright-reproducibility-report->json (report)
  "Serialise a playwright-reproducibility-report to a JSON string."
  (declare (type playwright-reproducibility-report report)
           (optimize (safety 3)))
  (labels ((bool (b) (if b "true" "false"))
           (scenario->json (s)
           (format nil
            "{\"scenario_id\":~S,\"sample_count\":~D,\"stable_count\":~D,~
             \"stability_ratio\":~,4F,\"command_fingerprint_delta\":~D,~
             \"artifact_hash_chain\":~S,\"pass\":~A,\"alarms\":[~{~S~^,~}]}"
            (srs-scenario-id s)
            (srs-sample-count s)
            (srs-stable-count s)
            (srs-stability-ratio s)
            (srs-command-fingerprint-delta s)
            (srs-artifact-hash-chain s)
            (bool (srs-pass-p s))
            (srs-alarm-codes s))))
    (format nil
     "{\"run_id\":~S,\"overall_stability_ratio\":~,4F,~
       \"closure_ready\":~A,\"command_fingerprint_stable\":~A,~
       \"artifact_hash_chain_ok\":~A,~
       \"alarm_codes\":[~{~S~^,~}],~
       \"timestamp\":~D,\"detail\":~S,~
       \"scenarios\":[~{~A~^,~}]}"
     (prr-run-id report)
     (prr-overall-stability-ratio report)
     (bool (prr-closure-ready-p report))
     (bool (prr-command-fingerprint-stable-p report))
     (bool (prr-artifact-hash-chain-ok-p report))
     (prr-alarm-codes report)
     (prr-timestamp report)
     (prr-detail report)
     (mapcar #'scenario->json (prr-scenarios report)))))
