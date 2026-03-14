;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; endpoint-classifier-tests.lisp — Fixture matrix for endpoint classification

(in-package #:orrery/harness-tests)

(define-test endpoint-classifier-tests)

;;; Body shape detection
(define-test (endpoint-classifier-tests body-shape-detection)
  (is eq :json-object (orrery/adapter/openclaw:detect-body-shape "{\"ok\":true}"))
  (is eq :json-array  (orrery/adapter/openclaw:detect-body-shape "[1,2]"))
  (is eq :html        (orrery/adapter/openclaw:detect-body-shape "<html><body>"))
  (is eq :html        (orrery/adapter/openclaw:detect-body-shape "<!DOCTYPE html>"))
  (is eq :empty       (orrery/adapter/openclaw:detect-body-shape ""))
  (is eq :text        (orrery/adapter/openclaw:detect-body-shape "plain text")))

;;; Classification fixture matrix
(define-test (endpoint-classifier-tests fixture-matrix)
  ;; JSON API response → openclaw-json
  (let ((c (orrery/adapter/openclaw:classify-endpoint-response
            200 "application/json" "{\"status\":\"ok\"}")))
    (is eq :openclaw-json (orrery/adapter/openclaw:ec-surface c))
    (is = 200 (orrery/adapter/openclaw:ec-http-status c)))

  ;; HTML control plane → html-control-plane
  (let ((c (orrery/adapter/openclaw:classify-endpoint-response
            200 "text/html" "<html><body>Dashboard</body></html>")))
    (is eq :html-control-plane (orrery/adapter/openclaw:ec-surface c)))

  ;; JSON body but wrong content-type → unknown-json
  (let ((c (orrery/adapter/openclaw:classify-endpoint-response
            200 "text/plain" "{\"data\":1}")))
    (is eq :unknown-json (orrery/adapter/openclaw:ec-surface c)))

  ;; Empty body → empty
  (let ((c (orrery/adapter/openclaw:classify-endpoint-response
            204 "application/json" "")))
    (is eq :empty (orrery/adapter/openclaw:ec-surface c)))

  ;; HTML content-type with non-HTML body → html-control-plane (trusts header)
  (let ((c (orrery/adapter/openclaw:classify-endpoint-response
            200 "text/html; charset=utf-8" "not html at all")))
    (is eq :html-control-plane (orrery/adapter/openclaw:ec-surface c)))

  ;; JSON array response → openclaw-json
  (let ((c (orrery/adapter/openclaw:classify-endpoint-response
            200 "application/json" "[{\"id\":1}]")))
    (is eq :openclaw-json (orrery/adapter/openclaw:ec-surface c))))

;;; Confidence scores
(define-test (endpoint-classifier-tests confidence-scores)
  (let ((json-c (orrery/adapter/openclaw:classify-endpoint-response
                 200 "application/json" "{\"ok\":true}"))
        (html-c (orrery/adapter/openclaw:classify-endpoint-response
                 200 "text/html" "<html>")))
    (true (> (orrery/adapter/openclaw:ec-confidence json-c)
             (orrery/adapter/openclaw:ec-confidence html-c)))))

;;; Fallback routing integration — classifier feeds into evaluate-endpoint-fallback
(define-test (endpoint-classifier-tests fallback-integration)
  ;; Known HTML path should produce fallback hint
  (let ((fb (orrery/adapter/openclaw:evaluate-endpoint-fallback
             "http://localhost:18789" "/sessions")))
    (false (orrery/adapter/openclaw:fb-usable-p fb))
    ;; Classifier would detect HTML on this path
    (let ((c (orrery/adapter/openclaw:classify-endpoint-response
              200 "text/html" "<html>sessions UI</html>")))
      (is eq :html-control-plane (orrery/adapter/openclaw:ec-surface c))
      ;; Resolved URL should be the API alternative
      (true (stringp (orrery/adapter/openclaw:fb-resolved-url fb))))))
