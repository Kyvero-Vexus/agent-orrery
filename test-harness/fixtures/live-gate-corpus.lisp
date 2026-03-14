;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; live-gate-corpus.lisp — Typed fixture corpus for live-gate compatibility
;;;
;;; Provides deterministic response fixtures representing each response family
;;; (OpenClaw JSON API, HTML control-plane, auth-gated, unreachable, unknown)
;;; for CI contract testing without live endpoints.

(in-package #:orrery/harness-tests)

;;; ─── Fixture type ───

(deftype fixture-family ()
  '(member :openclaw-api :html-control-plane :auth-gated :unreachable :unknown))

(defstruct (gate-fixture
             (:constructor make-gate-fixture
                 (&key name family http-status content-type body
                       expected-surface expected-ready-p expected-problem))
             (:conc-name gf-))
  (name "" :type string)
  (family :unknown :type fixture-family)
  (http-status 200 :type fixnum)
  (content-type "text/html" :type string)
  (body "" :type string)
  (expected-surface :error :type keyword)
  (expected-ready-p nil :type boolean)
  (expected-problem nil :type (or null keyword)))

;;; ─── Fixture corpus ───

(defparameter *live-gate-fixtures*
  (list
   ;; F1: Healthy OpenClaw JSON API endpoint
   (make-gate-fixture
    :name "openclaw-json-health"
    :family :openclaw-api
    :http-status 200
    :content-type "application/json"
    :body "{\"status\":\"ok\",\"version\":\"0.9.3\"}"
    :expected-surface :openclaw-json
    :expected-ready-p t
    :expected-problem nil)

   ;; F2: OpenClaw JSON sessions listing
   (make-gate-fixture
    :name "openclaw-json-sessions"
    :family :openclaw-api
    :http-status 200
    :content-type "application/json"
    :body "[{\"id\":\"abc\",\"status\":\"active\"}]"
    :expected-surface :openclaw-json
    :expected-ready-p t
    :expected-problem nil)

   ;; F3: HTML control-plane (dashboard)
   (make-gate-fixture
    :name "html-dashboard"
    :family :html-control-plane
    :http-status 200
    :content-type "text/html"
    :body "<!DOCTYPE html><html><head><title>OpenClaw</title></head><body>Dashboard</body></html>"
    :expected-surface :html-control-plane
    :expected-ready-p nil
    :expected-problem :html-detected)

   ;; F4: HTML control-plane (login page)
   (make-gate-fixture
    :name "html-login"
    :family :html-control-plane
    :http-status 200
    :content-type "text/html; charset=utf-8"
    :body "<html><form action=\"/login\">Username: <input name=\"user\"/></form></html>"
    :expected-surface :html-control-plane
    :expected-ready-p nil
    :expected-problem :html-detected)

   ;; F5: Auth-gated 401
   (make-gate-fixture
    :name "auth-401-bearer"
    :family :auth-gated
    :http-status 401
    :content-type "application/json"
    :body "{\"error\":\"unauthorized\",\"message\":\"Bearer token required\"}"
    :expected-surface :error
    :expected-ready-p nil
    :expected-problem :authentication-required)

   ;; F6: Auth-gated 403
   (make-gate-fixture
    :name "auth-403-forbidden"
    :family :auth-gated
    :http-status 403
    :content-type "application/json"
    :body "{\"error\":\"forbidden\"}"
    :expected-surface :error
    :expected-ready-p nil
    :expected-problem :authentication-required)

   ;; F7: Unreachable (connection refused)
   (make-gate-fixture
    :name "unreachable-connrefused"
    :family :unreachable
    :http-status 0
    :content-type ""
    :body ""
    :expected-surface :error
    :expected-ready-p nil
    :expected-problem :endpoint-unreachable)

   ;; F8: Unreachable (DNS failure)
   (make-gate-fixture
    :name "unreachable-dns"
    :family :unreachable
    :http-status 0
    :content-type ""
    :body ""
    :expected-surface :error
    :expected-ready-p nil
    :expected-problem :endpoint-unreachable)

   ;; F9: Unknown surface (XML) — classifier maps :error surface to :unreachable
   ;; so we use a non-error, non-json, non-html surface for true :unknown
   (make-gate-fixture
    :name "unknown-xml"
    :family :unknown
    :http-status 200
    :content-type "application/xml"
    :body "<?xml version=\"1.0\"?><response><status>ok</status></response>"
    :expected-surface :unknown-json
    :expected-ready-p nil
    :expected-problem :unknown-surface)

   ;; F10: Unknown surface (plaintext 200)
   (make-gate-fixture
    :name "unknown-plaintext"
    :family :unknown
    :http-status 200
    :content-type "text/plain"
    :body "OK"
    :expected-surface :unknown-json
    :expected-ready-p nil
    :expected-problem :unknown-surface)

   ;; F11: OpenClaw JSON with error status
   (make-gate-fixture
    :name "openclaw-json-500"
    :family :openclaw-api
    :http-status 500
    :content-type "application/json"
    :body "{\"error\":\"internal\",\"message\":\"server error\"}"
    :expected-surface :openclaw-json
    :expected-ready-p t
    :expected-problem nil)

   ;; F12: HTML with JSON content-type (misconfigured proxy)
   (make-gate-fixture
    :name "html-masquerading-as-json"
    :family :html-control-plane
    :http-status 200
    :content-type "application/json"
    :body "<!DOCTYPE html><html><body>Not JSON</body></html>"
    :expected-surface :html-control-plane
    :expected-ready-p nil
    :expected-problem :html-detected))
  "Fixture corpus covering all response families for live-gate contract testing.")
