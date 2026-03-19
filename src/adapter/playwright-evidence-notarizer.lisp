;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; playwright-evidence-notarizer.lisp — typed S1-S6 notarization + digest chain attestor
;;; Bead: agent-orrery-bcq9

(in-package #:orrery/adapter)

(defstruct (playwright-evidence-notarization (:conc-name pen-))
  (run-id "" :type string)
  (command "" :type string)
  (command-fingerprint 0 :type integer)
  (scenario-count 0 :type integer)
  (missing-scenarios nil :type list)
  (chain-digest "" :type string)
  (complete-p nil :type boolean)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (string) (values boolean &optional)) canonical-playwright-command-p)
 (ftype (function (list) (values string &optional)) compute-web-attestation-chain)
 (ftype (function (string string) (values playwright-evidence-notarization &optional))
        notarize-playwright-evidence)
 (ftype (function (string string) (values playwright-evidence-notarization &optional))
        write-playwright-evidence-notarization)
 (ftype (function (playwright-evidence-notarization) (values string &optional))
        playwright-evidence-notarization->json))

(defun canonical-playwright-command-p (command)
  (declare (type string command))
  (or (string= command "cd e2e && ./run-e2e.sh")
      (string= command "bash run-e2e.sh")))

(defun compute-web-attestation-chain (attestations)
  (declare (type list attestations))
  (let ((chain 0))
    (dolist (att attestations)
      (let ((chunk (format nil "~A|~D|~A|~A|~:[0~;1~]"
                           (wsa-scenario-id att)
                           (wsa-command-fingerprint att)
                           (wsa-screenshot-hash att)
                           (wsa-trace-hash att)
                           (wsa-attested-p att))))
        (setf chain (sxhash (format nil "~D|~A" chain chunk)))))
    (write-to-string chain)))

(defun notarize-playwright-evidence (artifact-root command)
  (declare (type string artifact-root command))
  (let* ((manifest (compile-playwright-evidence-manifest artifact-root command))
         (attestations (mapcar (lambda (sid)
                                 (build-web-scenario-attestation manifest sid))
                               *default-web-scenarios*))
         (missing (loop for att in attestations
                        unless (wsa-attested-p att)
                          collect (wsa-scenario-id att)))
         (command-ok (canonical-playwright-command-p command))
         (complete (and command-ok (null missing))))
    (make-playwright-evidence-notarization
     :run-id (format nil "playwright-notary-~D" (get-universal-time))
     :command command
     :command-fingerprint (sxhash command)
     :scenario-count (length *default-web-scenarios*)
     :missing-scenarios missing
     :chain-digest (compute-web-attestation-chain attestations)
     :complete-p complete
     :timestamp (get-universal-time))))

(defun write-playwright-evidence-notarization (artifact-root command)
  (declare (type string artifact-root command))
  (let* ((note (notarize-playwright-evidence artifact-root command))
         (out (merge-pathnames "playwright-evidence-notarization.json" (pathname artifact-root))))
    (with-open-file (s out :direction :output :if-exists :supersede)
      (write-string (playwright-evidence-notarization->json note) s))
    note))

(defun playwright-evidence-notarization->json (note)
  (declare (type playwright-evidence-notarization note))
  (format nil
          "{\"run_id\":\"~A\",\"command\":\"~A\",\"command_fingerprint\":~D,\"scenario_count\":~D,\"missing_count\":~D,\"chain_digest\":\"~A\",\"complete\":~:[false~;true~],\"timestamp\":~D}"
          (pen-run-id note)
          (pen-command note)
          (pen-command-fingerprint note)
          (pen-scenario-count note)
          (length (pen-missing-scenarios note))
          (pen-chain-digest note)
          (pen-complete-p note)
          (pen-timestamp note)))
