;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; views.lisp — Pure HTML generators for web dashboard
;;; Bead: agent-orrery-eb0.4.1

(in-package #:orrery/web)

;;; ─── Page Shell ───

(defun render-page (title body-html)
  "Wrap body HTML in a complete page. Pure."
  (format nil "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>~A</title>~
<style>body{font-family:monospace;margin:20px;background:#1a1a2e;color:#e0e0e0}~
table{border-collapse:collapse;width:100%}th,td{border:1px solid #333;padding:8px;text-align:left}~
th{background:#16213e}a{color:#0f3460}nav{margin-bottom:20px}nav a{margin-right:15px;color:#e94560}~
.badge{padding:2px 8px;border-radius:3px}.active{background:#2d6a4f;color:white}~
.idle{background:#e9c46a;color:black}.closed{background:#e76f51;color:white}~
h1{color:#e94560}h2{color:#0f3460}</style></head><body>~
<nav><a href=\"/\">Dashboard</a><a href=\"/sessions\">Sessions</a>~
<a href=\"/cron\">Cron</a><a href=\"/alerts\">Alerts</a></nav>~A</body></html>"
          title body-html))

;;; ─── Dashboard ───

(defun render-dashboard-html (sessions cron-jobs health alerts)
  "Render dashboard overview page. Pure."
  (render-page "Agent Orrery Dashboard"
    (format nil "<h1>Agent Orrery Dashboard</h1>~
<div id=\"summary\">~
<p>Sessions: <span id=\"session-count\">~D</span></p>~
<p>Active: <span id=\"active-count\">~D</span></p>~
<p>Cron Jobs: <span id=\"cron-count\">~D</span></p>~
<p>Health Components: <span id=\"health-count\">~D</span></p>~
<p>Alerts: <span id=\"alert-count\">~D</span></p></div>"
            (length sessions)
            (count :active sessions :key #'sr-status)
            (length cron-jobs)
            (length health)
            (length alerts))))

;;; ─── Sessions ───

(defun render-sessions-html (sessions)
  "Render session list page. Pure."
  (render-page "Sessions"
    (format nil "<h1>Sessions</h1>~
<table id=\"sessions-table\"><thead><tr>~
<th>ID</th><th>Agent</th><th>Model</th><th>Status</th><th>Tokens</th><th>Cost</th></tr></thead>~
<tbody>~{~A~}</tbody></table>"
            (mapcar (lambda (s)
                      (format nil "<tr><td><a href=\"/sessions/~A\">~A</a></td>~
<td>~A</td><td>~A</td><td><span class=\"badge ~(~A~)\">~A</span></td>~
<td>~D</td><td>~D¢</td></tr>"
                              (sr-id s) (sr-id s) (sr-agent-name s) (sr-model s)
                              (sr-status s) (sr-status s)
                              (sr-total-tokens s) (sr-estimated-cost-cents s)))
                    sessions))))

;;; ─── Session Detail ───

(defun render-session-detail-html (session)
  "Render session detail page. Pure."
  (if (null session)
      (render-page "Not Found" "<h1>Session Not Found</h1>")
      (render-page (format nil "Session ~A" (sr-id session))
        (format nil "<h1>Session: ~A</h1>~
<div id=\"session-detail\">~
<p>Agent: <span id=\"agent\">~A</span></p>~
<p>Model: <span id=\"model\">~A</span></p>~
<p>Status: <span id=\"status\" class=\"badge ~(~A~)\">~A</span></p>~
<p>Tokens: <span id=\"tokens\">~D</span></p>~
<p>Cost: <span id=\"cost\">~D¢</span></p>~
<p>Channel: ~A</p></div>"
                (sr-id session) (sr-agent-name session) (sr-model session)
                (sr-status session) (sr-status session)
                (sr-total-tokens session) (sr-estimated-cost-cents session)
                (sr-channel session)))))

;;; ─── Cron ───

(defun render-cron-html (cron-jobs)
  "Render cron jobs page. Pure."
  (render-page "Cron Jobs"
    (format nil "<h1>Cron Jobs</h1>~
<table id=\"cron-table\"><thead><tr>~
<th>Name</th><th>Kind</th><th>Interval</th><th>Status</th></tr></thead>~
<tbody>~{~A~}</tbody></table>"
            (mapcar (lambda (c)
                      (format nil "<tr><td>~A</td><td>~A</td><td>~Ds</td>~
<td><span class=\"badge ~(~A~)\">~A</span></td></tr>"
                              (cr-name c) (cr-kind c) (cr-interval-s c)
                              (cr-status c) (cr-status c)))
                    cron-jobs))))

;;; ─── Alerts ───

(defun render-alerts-html (alerts)
  "Render alerts page. Pure."
  (render-page "Alerts"
    (format nil "<h1>Alerts</h1>~
<table id=\"alerts-table\"><thead><tr>~
<th>ID</th><th>Severity</th><th>Title</th></tr></thead>~
<tbody>~{~A~}</tbody></table>"
            (mapcar (lambda (a)
                      (format nil "<tr><td>~A</td><td>~A</td><td>~A</td></tr>"
                              (ar-id a) (ar-severity a) (ar-title a)))
                    alerts))))
