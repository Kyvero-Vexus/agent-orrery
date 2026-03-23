;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; protocol-version-contract.lisp — typed protocol version negotiation contract
;;; Bead: agent-orrery-7mki

(in-package #:orrery/adapter)

;;; ── Version contract types ──────────────────────────────────────────────────

(defstruct (version-contract-entry (:conc-name vce-))
  "Typed version contract for one protocol surface."
  (surface "" :type string)
  (schema-version "1.0" :type string)
  (compatible-p nil :type boolean)
  (required-fields nil :type list)
  (detail "" :type string))

(defstruct (version-negotiation-contract (:conc-name vnc-))
  "Typed cross-UI version negotiation contract with compatibility matrix."
  (run-id "" :type string)
  (tui-version "1.0" :type string)
  (web-version "1.0" :type string)
  (entries nil :type list)
  (all-compatible-p nil :type boolean)
  (timestamp 0 :type integer)
  (detail "" :type string))

;;; ── Declaims ────────────────────────────────────────────────────────────────

(declaim
 (ftype (function (string string) (values version-contract-entry &optional))
        make-version-contract-entry*)
 (ftype (function () (values version-negotiation-contract &optional))
        compile-version-negotiation-contract)
 (ftype (function (version-negotiation-contract) (values string &optional))
        version-negotiation-contract->json))

;;; ── Implementation ──────────────────────────────────────────────────────────

(defun make-version-contract-entry* (surface schema-version)
  "Build a typed version contract entry for one protocol surface."
  (declare (type string surface schema-version))
  (let* ((surface-key (alexandria:make-keyword (string-upcase surface)))
         (schema (orrery/protocol-schema:default-schema
                  (ecase surface-key
                    ((:tui) :tui)
                    ((:web) :web))
                  :status))
         (required (mapcar #'orrery/protocol-schema:sf-name
                           (orrery/protocol-schema:ss-fields schema)))
         (compatible t)) ; Assume compatible if schema exists
    (make-version-contract-entry
     :surface surface
     :schema-version schema-version
     :compatible-p compatible
     :required-fields required
     :detail (format nil "~A v~A: ~D required fields"
                     surface schema-version (length required)))))

(defun compile-version-negotiation-contract ()
  "Compile cross-UI version negotiation contract with compatibility matrix."
  (let* ((tui-entry (make-version-contract-entry* "TUI" "1.0"))
         (web-entry (make-version-contract-entry* "WEB" "1.0"))
         (entries (list tui-entry web-entry))
         (all-compat (every #'vce-compatible-p entries))
         (timestamp (get-universal-time)))
    (make-version-negotiation-contract
     :run-id (format nil "version-contract-~D" timestamp)
     :tui-version "1.0"
     :web-version "1.0"
     :entries entries
     :all-compatible-p all-compat
     :timestamp timestamp
     :detail (if all-compat
                 "ALL_SURFACES_COMPATIBLE"
                 "COMPATIBILITY_MISMATCH"))))

(defun version-negotiation-contract->json (contract)
  "Serialize version negotiation contract to deterministic JSON."
  (declare (type version-negotiation-contract contract))
  (with-output-to-string (s)
    (format s "{\"run_id\":\"~A\",\"tui_version\":\"~A\",\"web_version\":\"~A\",\"all_compatible\":~A,\"timestamp\":~D,\"entries\":["
            (vnc-run-id contract)
            (vnc-tui-version contract)
            (vnc-web-version contract)
            (if (vnc-all-compatible-p contract) "true" "false")
            (vnc-timestamp contract))
    (loop for e in (vnc-entries contract)
          for first = t then nil
          unless first do (write-char #\, s)
          do (format s "{\"surface\":\"~A\",\"version\":\"~A\",\"compatible\":~A,\"required_fields\":~D,\"detail\":\"~A\"}"
                     (vce-surface e)
                     (vce-schema-version e)
                     (if (vce-compatible-p e) "true" "false")
                     (length (vce-required-fields e))
                     (vce-detail e)))
    (format s "],\"detail\":\"~A\"}" (vnc-detail contract))))
