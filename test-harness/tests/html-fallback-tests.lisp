;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; html-fallback-tests.lisp — Tests for HTML endpoint fallback + remediation

(in-package #:orrery/harness-tests)

(define-test html-fallback-tests)

(define-test (html-fallback-tests detect-content-kind-classification)
  (is eq :json (orrery/adapter/openclaw:detect-content-kind "{\"ok\":true}"))
  (is eq :json (orrery/adapter/openclaw:detect-content-kind "[1,2,3]"))
  (is eq :html (orrery/adapter/openclaw:detect-content-kind "<html><body>hi</body></html>"))
  (is eq :html (orrery/adapter/openclaw:detect-content-kind "<!DOCTYPE html>"))
  (is eq :unknown (orrery/adapter/openclaw:detect-content-kind ""))
  (is eq :unknown (orrery/adapter/openclaw:detect-content-kind "plain text")))

(define-test (html-fallback-tests evaluate-endpoint-fallback-known-path)
  (let ((fb (orrery/adapter/openclaw:evaluate-endpoint-fallback "http://localhost:18789" "/sessions")))
    (false (orrery/adapter/openclaw:fb-usable-p fb))
    (true (stringp (orrery/adapter/openclaw:fb-resolved-url fb)))
    (is string= "http://localhost:18789/api/v1/sessions"
        (orrery/adapter/openclaw:fb-resolved-url fb))
    (is = 1 (length (orrery/adapter/openclaw:fb-hints fb)))))

(define-test (html-fallback-tests evaluate-endpoint-fallback-unknown-path)
  (let ((fb (orrery/adapter/openclaw:evaluate-endpoint-fallback "http://localhost:18789" "/unknown")))
    (true (orrery/adapter/openclaw:fb-usable-p fb))
    (is = 0 (length (orrery/adapter/openclaw:fb-hints fb)))))

(define-test (html-fallback-tests evaluate-all-endpoints-batch)
  (let ((results (orrery/adapter/openclaw:evaluate-all-endpoints
                  "http://localhost:18789"
                  '("/health" "/sessions" "/unknown"))))
    (is = 3 (length results))
    ;; First two are known paths → not directly usable
    (false (orrery/adapter/openclaw:fb-usable-p (first results)))
    (false (orrery/adapter/openclaw:fb-usable-p (second results)))
    ;; Unknown → usable (no fallback needed)
    (true (orrery/adapter/openclaw:fb-usable-p (third results)))))
