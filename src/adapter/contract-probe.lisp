;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; contract-probe.lisp — Typed live-endpoint contract probe + diagnostics

(in-package #:orrery/adapter/openclaw)

(defstruct (probe-mismatch
             (:constructor make-probe-mismatch (&key endpoint category detail)))
  (endpoint "" :type string)
  (category :unknown :type keyword)
  (detail "" :type string))

(defstruct (probe-endpoint-result
             (:constructor make-probe-endpoint-result
                 (&key endpoint ok-p http-status content-type json-p mismatches)))
  (endpoint "" :type string)
  (ok-p nil :type boolean)
  (http-status 0 :type fixnum)
  (content-type "" :type string)
  (json-p nil :type boolean)
  (mismatches '() :type list))

(defstruct (probe-report
             (:constructor make-probe-report (&key base-url overall-ok-p results)))
  (base-url "" :type string)
  (overall-ok-p nil :type boolean)
  (results '() :type list))

(declaim (ftype (function (&key (:base-url string)
                                (:api-token (or null string))
                                (:timeout-s fixnum))
                         probe-report)
                openclaw-live-contract-probe)
         (ftype (function (string) (values boolean &optional)) %looks-like-html-p)
         (ftype (function (string) (values (or null hash-table list) (or null string) &optional))
                %parse-json-safe)
         (ftype (function (hash-table list) (values list &optional)) %missing-required-keys)
         (ftype (function (openclaw-adapter string list)
                         probe-endpoint-result)
                %probe-endpoint))

(defun %looks-like-html-p (body)
  (let ((trimmed (string-left-trim '(#\Space #\Tab #\Newline #\Return) body)))
    (or (and (>= (length trimmed) 5)
             (string-equal "<html" trimmed :end2 5))
        (and (>= (length trimmed) 9)
             (string-equal "<!doctype" trimmed :end2 9))
        (and (> (length trimmed) 0) (char= (char trimmed 0) #\<)))))

(defun %parse-json-safe (body)
  (handler-case
      (values (com.inuoe.jzon:parse body) nil)
    (error (e)
      (values nil (princ-to-string e)))))

(defun %missing-required-keys (payload required-keys)
  (let ((missing '()))
    (dolist (k required-keys)
      (unless (and (hash-table-p payload)
                   (multiple-value-bind (v presentp) (gethash k payload)
                     (declare (ignore v))
                     presentp))
        (push k missing)))
    (nreverse missing)))

(defun %endpoint-url (adapter path)
  (format nil "~A~A"
          (string-right-trim "/" (openclaw-base-url adapter))
          path))

(defun %probe-endpoint (adapter path required-keys)
  (let ((url (%endpoint-url adapter path))
        (headers (%headers adapter))
        (mismatches '())
        (status 0)
        (content-type "")
        (json-p nil)
        (ok-p nil))
    (labels ((add-mismatch (category fmt &rest args)
               (push (make-probe-mismatch
                      :endpoint path
                      :category category
                      :detail (apply #'format nil fmt args))
                     mismatches)))
      (handler-case
          (multiple-value-bind (body code response-headers)
              (dexador:get url :headers headers :connect-timeout (openclaw-timeout-s adapter))
            (setf status (or code 200)
                  content-type (or (cdr (assoc "content-type" response-headers :test #'string-equal)) ""))
            (when (%looks-like-html-p body)
              (add-mismatch :html-response "Endpoint ~A returned HTML payload" path))
            (multiple-value-bind (payload parse-error)
                (%parse-json-safe body)
              (if payload
                  (setf json-p t)
                  (add-mismatch :json-parse "JSON parse failed at ~A: ~A" path parse-error))
              (when (and payload (hash-table-p payload))
                (let ((missing (%missing-required-keys payload required-keys)))
                  (dolist (k missing)
                    (add-mismatch :missing-key "Missing required key ~A at ~A" k path)))))
            (setf ok-p (null mismatches)))
        (dexador.error:http-request-failed (e)
          (let ((code (or (ignore-errors (dexador.error:response-status e)) 0)))
            (setf status code)
            (add-mismatch :http-status "HTTP request failed (~A) at ~A" code path)))
        (error (e)
          (add-mismatch :transport "Transport error at ~A: ~A" path e))))
    (make-probe-endpoint-result
     :endpoint path
     :ok-p ok-p
     :http-status status
     :content-type content-type
     :json-p json-p
     :mismatches (nreverse mismatches))))

(defun openclaw-live-contract-probe (&key (base-url "http://localhost:7474") (api-token nil) (timeout-s 5))
  "Probe expected OpenClaw JSON endpoint contracts and emit typed mismatch diagnostics."
  (let* ((adapter (make-openclaw-adapter :base-url base-url :api-token api-token :timeout-s timeout-s))
         (checks (list (%probe-endpoint adapter "/health" '("ok"))
                       (%probe-endpoint adapter "/sessions" '("ok" "result"))
                       (%probe-endpoint adapter "/events" '("ok" "result"))
                       (%probe-endpoint adapter "/snapshot" '("ok" "result"))))
         (overall (every #'probe-endpoint-result-ok-p checks)))
    (make-probe-report :base-url base-url :overall-ok-p overall :results checks)))
