;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; e2e-gate.lisp — Deterministic Epic 5 CLIM gate scenarios S1-S6
;;; Bead: agent-orrery-eb0.5.5

(in-package #:orrery/mcclim)

(defstruct (scenario-result (:conc-name s5r-))
  "Result for one Epic-5 scenario."
  (id "" :type string)
  (pass-p nil :type boolean)
  (detail "" :type string))

(declaim (ftype (function (symbol) (values boolean &optional)) command-exists-p))
(defun command-exists-p (sym)
  "True if SYM names a bound command function."
  (not (null (and (fboundp sym) t))))

(declaim (ftype (function () (values list &optional)) run-epic5-scenarios))
(defun run-epic5-scenarios ()
  "Run deterministic CLIM gate scenarios S1-S6."
  (let ((results nil))
    ;; S1: Frame class + panes are present
    (push (make-scenario-result
           :id "S1"
           :pass-p (not (null (find-class 'orrery-dashboard nil)))
           :detail "Frame class orrery-dashboard exists")
          results)

    ;; S2: Keyboard help discoverability exists
    (push (make-scenario-result
           :id "S2"
           :pass-p (not (null (and (command-exists-p 'com-help)
                                   (assoc "?" *keyboard-shortcuts* :test #'string=))))
           :detail "Keyboard help command and ? binding exist")
          results)

    ;; S3: Focus traversal parity (wrap navigation)
    (push (make-scenario-result
           :id "S3"
           :pass-p (and (= (wrap-index -1 0 5) 5)
                        (= (wrap-index 6 0 5) 0)
                        (>= (length *focus-order*) 6))
           :detail "Focus traversal wraps and includes 6 panes")
          results)

    ;; S4: Session/Cron operation commands exist
    (push (make-scenario-result
           :id "S4"
           :pass-p (and (command-exists-p 'com-list-sessions)
                        (command-exists-p 'com-list-cron)
                        (command-exists-p 'com-trigger-cron)
                        (command-exists-p 'com-pause-cron)
                        (command-exists-p 'com-resume-cron))
           :detail "Session/Cron command table coverage")
          results)

    ;; S5: Inspector command coverage
    (push (make-scenario-result
           :id "S5"
           :pass-p (and (command-exists-p 'com-session-detail)
                        (command-exists-p 'com-event-detail)
                        (command-exists-p 'com-alert-detail)
                        (command-exists-p 'com-health-detail)
                        (command-exists-p 'com-summary))
           :detail "Inspectors for sessions/events/alerts/health + summary")
          results)

    ;; S6: Quit + status hint parity
    (push (make-scenario-result
           :id "S6"
           :pass-p (not (null (and (command-exists-p 'com-quit)
                                   (search "q quit" (string-downcase (status-key-hint-line))))))
           :detail "Quit command + status hint exposes q")
          results)

    (nreverse results)))

(declaim (ftype (function (list) (values string &optional)) epic5-results->json))
(defun epic5-results->json (results)
  "Deterministic JSON payload for gate output."
  (format nil
          "{\"suite\":\"epic5-clim-gate\",\"total\":~D,\"passed\":~D,\"failed\":~D,\"scenarios\":[~{~A~^,~}]}"
          (length results)
          (count-if #'s5r-pass-p results)
          (count-if-not #'s5r-pass-p results)
          (mapcar (lambda (r)
                    (format nil
                            "{\"id\":\"~A\",\"pass\":~A,\"detail\":\"~A\"}"
                            (s5r-id r)
                            (if (s5r-pass-p r) "true" "false")
                            (s5r-detail r)))
                  results)))
