;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; mcp-tui-witness-verifier.lisp — signature + deterministic lineage verifier
;;; Bead: agent-orrery-kh0z

(in-package #:orrery/adapter)

(defstruct (mcp-tui-witness-verification (:conc-name mtwv-))
  (pass-p nil :type boolean)
  (signature-valid-p nil :type boolean)
  (command-lineage-valid-p nil :type boolean)
  (digest-map-valid-p nil :type boolean)
  (closure-semantics-valid-p nil :type boolean)
  (detail "" :type string)
  (timestamp 0 :type integer))

(declaim
 (ftype (function (mcp-tui-witness-bundle) (values string &optional)) mcp-tui-witness-expected-signature)
 (ftype (function (mcp-tui-witness-bundle string) (values mcp-tui-witness-verification &optional))
        verify-mcp-tui-witness-bundle)
 (ftype (function (mcp-tui-witness-verification) (values string &optional))
        mcp-tui-witness-verification->json))

(defun mcp-tui-witness-expected-signature (bundle)
  (declare (type mcp-tui-witness-bundle bundle))
  (let* ((payload (with-output-to-string (out)
                    (format out "~D|~A|"
                            (mtwb-command-fingerprint bundle)
                            (if (mtwb-closure-pass-p bundle) "1" "0"))
                    (dolist (pair (mtwb-transcript-digest-map bundle))
                      (format out "~A=~A;" (car pair) (cdr pair)))))
         (fingerprint (sxhash payload)))
    (format nil "witness-~36R" (abs fingerprint))))

(defun %digest-map-complete-p (digest-map)
  (declare (type list digest-map))
  (and (= (length digest-map) (length *mcp-tui-required-scenarios*))
       (every (lambda (sid) (assoc sid digest-map :test #'string=))
              *mcp-tui-required-scenarios*)))

(defun verify-mcp-tui-witness-bundle (bundle expected-command)
  (declare (type mcp-tui-witness-bundle bundle)
           (type string expected-command))
  (let* ((expected-signature (mcp-tui-witness-expected-signature bundle))
         (signature-ok (string= (mtwb-signature bundle) expected-signature))
         (lineage-ok (and (string= expected-command (mtwb-deterministic-command bundle))
                          (string= expected-command *mcp-tui-deterministic-command*)
                          (mtwb-command-match-p bundle)
                          (= (mtwb-command-fingerprint bundle)
                             (command-fingerprint expected-command))))
         (digest-ok (%digest-map-complete-p (mtwb-transcript-digest-map bundle)))
         (closure-ok (or (and (mtwb-pass-p bundle)
                              (mtwb-closure-pass-p bundle)
                              (null (mtwb-missing-scenarios bundle)))
                         (not (mtwb-pass-p bundle))))
         (pass (and signature-ok lineage-ok digest-ok closure-ok)))
    (make-mcp-tui-witness-verification
     :pass-p pass
     :signature-valid-p signature-ok
     :command-lineage-valid-p lineage-ok
     :digest-map-valid-p digest-ok
     :closure-semantics-valid-p closure-ok
     :detail (format nil "signature_ok=~A lineage_ok=~A digest_ok=~A closure_ok=~A"
                     signature-ok lineage-ok digest-ok closure-ok)
     :timestamp (get-universal-time))))

(defun mcp-tui-witness-verification->json (verification)
  (declare (type mcp-tui-witness-verification verification))
  (format nil
          "{\"pass\":~A,\"signature_valid\":~A,\"command_lineage_valid\":~A,\"digest_map_valid\":~A,\"closure_semantics_valid\":~A,\"detail\":\"~A\",\"timestamp\":~D}"
          (if (mtwv-pass-p verification) "true" "false")
          (if (mtwv-signature-valid-p verification) "true" "false")
          (if (mtwv-command-lineage-valid-p verification) "true" "false")
          (if (mtwv-digest-map-valid-p verification) "true" "false")
          (if (mtwv-closure-semantics-valid-p verification) "true" "false")
          (mtwv-detail verification)
          (mtwv-timestamp verification)))
