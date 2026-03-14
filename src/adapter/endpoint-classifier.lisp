;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; endpoint-classifier.lisp — Typed endpoint classifier for surface detection
;;;
;;; Classifies HTTP responses into endpoint surface types and provides
;;; structured classification results consumed by fallback routing.

(in-package #:orrery/adapter/openclaw)

;;; ─── Classification types ───

(deftype endpoint-surface ()
  '(member :openclaw-json :html-control-plane :unknown-json :empty :error))

(defstruct (endpoint-classification
             (:constructor make-endpoint-classification
                 (&key path surface http-status content-type body-shape confidence))
             (:conc-name ec-))
  (path "" :type string)
  (surface :unknown-json :type endpoint-surface)
  (http-status 0 :type fixnum)
  (content-type "" :type string)
  (body-shape :empty :type keyword)
  (confidence 1.0 :type single-float))

(declaim (ftype (function (fixnum string string) (values endpoint-classification &optional))
                classify-endpoint-response)
         (ftype (function (string) (values keyword &optional)) detect-body-shape))

(defun detect-body-shape (body)
  "Classify body shape: :json-object, :json-array, :html, :empty, :text."
  (declare (type string body))
  (let ((trimmed (string-left-trim '(#\Space #\Tab #\Newline #\Return) body)))
    (cond
      ((zerop (length trimmed)) :empty)
      ((char= (char trimmed 0) #\{) :json-object)
      ((char= (char trimmed 0) #\[) :json-array)
      ((%looks-like-html-p trimmed) :html)
      (t :text))))

(defun classify-endpoint-response (http-status content-type body)
  "Classify an endpoint response into a surface type with confidence."
  (declare (type fixnum http-status) (type string content-type body))
  (let* ((shape (detect-body-shape body))
         (ct-lower (string-downcase content-type))
         (json-ct-p (or (search "application/json" ct-lower)
                        (search "text/json" ct-lower))))
    (make-endpoint-classification
     :path ""
     :http-status http-status
     :content-type content-type
     :body-shape shape
     :surface (cond
                ;; HTML body or HTML content-type → control plane
                ((eq shape :html) :html-control-plane)
                ((search "text/html" ct-lower) :html-control-plane)
                ;; JSON content-type + JSON body → OpenClaw candidate
                ((and json-ct-p (member shape '(:json-object :json-array)))
                 :openclaw-json)
                ;; JSON body but wrong content-type
                ((member shape '(:json-object :json-array)) :unknown-json)
                ;; Empty response
                ((eq shape :empty) :empty)
                ;; Unrecognized
                (t :error))
     :confidence (cond
                   ((and json-ct-p (member shape '(:json-object :json-array))) 0.95)
                   ((eq shape :html) 0.90)
                   (t 0.5)))))
