;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; html-fallback.lisp — Typed adapter fallback for HTML endpoint detection/mapping
;;;
;;; Detects control-plane HTML endpoints and returns typed remediation
;;; errors or maps to compatible JSON API routes when possible.

(in-package #:orrery/adapter/openclaw)

;;; ─── Remediation hint structure ───

(defstruct (remediation-hint
             (:constructor make-remediation-hint (&key endpoint problem suggestion alternative-url))
             (:conc-name rh-))
  (endpoint "" :type string)
  (problem :html-detected :type keyword)
  (suggestion "" :type string)
  (alternative-url nil :type (or null string)))

(defstruct (fallback-result
             (:constructor make-fallback-result (&key usable-p original-url resolved-url hints))
             (:conc-name fb-))
  (usable-p nil :type boolean)
  (original-url "" :type string)
  (resolved-url nil :type (or null string))
  (hints '() :type list))

;;; ─── Content detection ───

(declaim (ftype (function (string) (values keyword &optional)) detect-content-kind)
         (ftype (function (string string) (values fallback-result &optional)) evaluate-endpoint-fallback)
         (ftype (function (string) (values (or null string) &optional)) %find-api-alternative))

(defun detect-content-kind (body)
  "Classify response body as :json, :html, or :unknown."
  (declare (type string body))
  (let ((trimmed (string-left-trim '(#\Space #\Tab #\Newline #\Return) body)))
    (cond
      ((zerop (length trimmed)) :unknown)
      ((or (char= (char trimmed 0) #\{)
           (char= (char trimmed 0) #\[))
       :json)
      ((%looks-like-html-p trimmed) :html)
      (t :unknown))))

;;; ─── Known control-plane route mappings ───

(defparameter *html-to-api-route-map*
  '(("/sessions"  . "/api/v1/sessions")
    ("/health"    . "/api/v1/health")
    ("/events"    . "/api/v1/events")
    ("/snapshot"  . "/api/v1/snapshot")
    ("/cron"      . "/api/v1/cron")
    ("/alerts"    . "/api/v1/alerts")
    ("/"          . "/api/v1/health"))
  "Mapping from known HTML control-plane paths to potential JSON API alternatives.")

(defun %find-api-alternative (path)
  "Look up a potential JSON API route for a given HTML path."
  (declare (type string path))
  (cdr (assoc path *html-to-api-route-map* :test #'string=)))

;;; ─── Fallback evaluation ───

(defun evaluate-endpoint-fallback (base-url path)
  "Evaluate whether an endpoint can be used or needs fallback.
   Returns a FALLBACK-RESULT with hints for remediation."
  (declare (type string base-url path))
  (let* ((full-url (concatenate 'string base-url path))
         (hints '())
         (alternative (%find-api-alternative path)))
    (labels ((add-hint (problem suggestion &optional alt-url)
               (push (make-remediation-hint
                      :endpoint full-url
                      :problem problem
                      :suggestion suggestion
                      :alternative-url alt-url)
                     hints)))
      ;; Try the primary URL first (simulated — actual HTTP done by caller)
      ;; This function provides the mapping/hint layer, not transport
      (when alternative
        (add-hint :html-likely
                  (format nil "Path ~A is likely a control-plane HTML route. ~
                              Try API alternative: ~A~A"
                          path base-url alternative)
                  (concatenate 'string base-url alternative)))
      (make-fallback-result
       :usable-p (null hints)
       :original-url full-url
       :resolved-url (when alternative
                       (concatenate 'string base-url alternative))
       :hints (nreverse hints)))))

;;; ─── Batch evaluation for adapter bootstrap ───

(declaim (ftype (function (string list) (values list &optional)) evaluate-all-endpoints))

(defun evaluate-all-endpoints (base-url paths)
  "Evaluate fallback status for a list of endpoint paths."
  (declare (type string base-url) (type list paths))
  (mapcar (lambda (path) (evaluate-endpoint-fallback base-url path)) paths))
