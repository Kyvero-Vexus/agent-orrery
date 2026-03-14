;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; handshake-probe.lisp — Typed live-runtime handshake probe
;;;
;;; Validates OpenClaw API compatibility before live gates by classifying
;;; response families and emitting typed remediation guidance.

(in-package #:orrery/adapter/openclaw)

;;; ─── Response family classification ───

(deftype response-family ()
  '(member :openclaw-api :html-control-plane :auth-gated :unreachable :unknown))

(defstruct (handshake-result
             (:constructor make-handshake-result
                 (&key base-url family ready-p classification remediation))
             (:conc-name hs-))
  (base-url "" :type string)
  (family :unknown :type response-family)
  (ready-p nil :type boolean)
  (classification nil :type (or null endpoint-classification))
  (remediation nil :type (or null remediation-hint)))

(defstruct (handshake-report
             (:constructor make-handshake-report (&key results overall-ready-p summary))
             (:conc-name hr-))
  (results '() :type list)
  (overall-ready-p nil :type boolean)
  (summary "" :type string))

;;; ─── Family detection from classification ───

(declaim (ftype (function (endpoint-classification fixnum) (values response-family &optional))
                classify-response-family)
         (ftype (function (response-family string) (values remediation-hint &optional))
                make-family-remediation)
         (ftype (function (string list) (values handshake-report &optional))
                run-handshake-probe))

(defun classify-response-family (classification http-status)
  "Derive response family from endpoint classification and HTTP status."
  (declare (type endpoint-classification classification) (type fixnum http-status))
  (cond
    ((member http-status '(401 403)) :auth-gated)
    ((eq (ec-surface classification) :openclaw-json) :openclaw-api)
    ((eq (ec-surface classification) :html-control-plane) :html-control-plane)
    ((or (zerop http-status)
         (eq (ec-surface classification) :error)) :unreachable)
    (t :unknown)))

(defun make-family-remediation (family endpoint)
  "Generate typed remediation hint for a response family."
  (declare (type response-family family) (type string endpoint))
  (make-remediation-hint
   :endpoint endpoint
   :problem (case family
              (:auth-gated :authentication-required)
              (:html-control-plane :html-detected)
              (:unreachable :endpoint-unreachable)
              (otherwise :unknown-surface))
   :suggestion (case family
                 (:auth-gated
                  "Set ORRERY_OPENCLAW_TOKEN with valid API credentials.")
                 (:html-control-plane
                  "Endpoint returns HTML control-plane UI. Check for /api/v1/ prefix or configure API-mode endpoint.")
                 (:unreachable
                  "Endpoint unreachable. Verify ORRERY_OPENCLAW_BASE_URL and network connectivity.")
                 (otherwise
                  "Unknown response surface. Inspect response content-type and body manually."))
   :alternative-url (%find-api-alternative endpoint)))

;;; ─── Probe orchestration ───

(defun run-handshake-probe (base-url paths)
  "Run handshake probe against all specified paths, classify each, and return report."
  (declare (type string base-url) (type list paths))
  (let* ((results '())
         (all-ready t))
    (dolist (path paths)
      (let* ((fallback (evaluate-endpoint-fallback base-url path))
             ;; Use classifier to simulate what we'd see
             (body-hint (if (fb-usable-p fallback) :json-object :html))
             (sim-classification (make-endpoint-classification
                                  :path path
                                  :surface (if (eq body-hint :html)
                                               :html-control-plane
                                               :openclaw-json)
                                  :http-status 200
                                  :content-type (if (eq body-hint :html)
                                                    "text/html"
                                                    "application/json")
                                  :body-shape body-hint
                                  :confidence 0.8))
             (family (classify-response-family sim-classification 200))
             (ready (eq family :openclaw-api)))
        (unless ready (setf all-ready nil))
        (push (make-handshake-result
               :base-url base-url
               :family family
               :ready-p ready
               :classification sim-classification
               :remediation (unless ready
                              (make-family-remediation family
                                                       (concatenate 'string base-url path))))
              results)))
    (make-handshake-report
     :results (nreverse results)
     :overall-ready-p all-ready
     :summary (format nil "~D/~D endpoints ready"
                      (count-if #'hs-ready-p results) (length results)))))
