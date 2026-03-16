;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; configuration.lisp — Coalton typed configuration schema + defaults
;;;
;;; Bead: agent-orrery-1oe

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;; ─── Typed schema ───

  (define-type ConnectionConfig
    (ConnectionConfig String Integer String)) ; host, port, token

  (declare cc-host (ConnectionConfig -> String))
  (define (cc-host c)
    (match c ((ConnectionConfig host _ _) host)))

  (declare cc-port (ConnectionConfig -> Integer))
  (define (cc-port c)
    (match c ((ConnectionConfig _ port _) port)))

  (declare cc-token (ConnectionConfig -> String))
  (define (cc-token c)
    (match c ((ConnectionConfig _ _ token) token)))

  (define-type UiConfig
    (UiConfig String Integer Boolean)) ; theme, refresh-seconds, compact-mode

  (declare ui-theme (UiConfig -> String))
  (define (ui-theme u)
    (match u ((UiConfig theme _ _) theme)))

  (declare ui-refresh-seconds (UiConfig -> Integer))
  (define (ui-refresh-seconds u)
    (match u ((UiConfig _ refresh _) refresh)))

  (declare ui-compact-mode (UiConfig -> Boolean))
  (define (ui-compact-mode u)
    (match u ((UiConfig _ _ compact) compact)))

  (define-type FeatureFlags
    (FeatureFlags Boolean Boolean Boolean)) ; web, tui, mcclim

  (declare ff-web-enabled (FeatureFlags -> Boolean))
  (define (ff-web-enabled f)
    (match f ((FeatureFlags web _ _) web)))

  (declare ff-tui-enabled (FeatureFlags -> Boolean))
  (define (ff-tui-enabled f)
    (match f ((FeatureFlags _ tui _) tui)))

  (declare ff-mcclim-enabled (FeatureFlags -> Boolean))
  (define (ff-mcclim-enabled f)
    (match f ((FeatureFlags _ _ mcclim) mcclim)))

  (define-type RuntimeConfig
    (RuntimeConfig ConnectionConfig  ; connection
                   UiConfig          ; ui
                   Integer           ; polling-seconds
                   Integer           ; budget-warning-cents
                   Integer           ; budget-critical-cents
                   FeatureFlags))    ; feature flags

  (declare rc-connection (RuntimeConfig -> ConnectionConfig))
  (define (rc-connection cfg)
    (match cfg ((RuntimeConfig c _ _ _ _ _) c)))

  (declare rc-ui (RuntimeConfig -> UiConfig))
  (define (rc-ui cfg)
    (match cfg ((RuntimeConfig _ u _ _ _ _) u)))

  (declare rc-polling-seconds (RuntimeConfig -> Integer))
  (define (rc-polling-seconds cfg)
    (match cfg ((RuntimeConfig _ _ p _ _ _) p)))

  (declare rc-budget-warning-cents (RuntimeConfig -> Integer))
  (define (rc-budget-warning-cents cfg)
    (match cfg ((RuntimeConfig _ _ _ warn _ _) warn)))

  (declare rc-budget-critical-cents (RuntimeConfig -> Integer))
  (define (rc-budget-critical-cents cfg)
    (match cfg ((RuntimeConfig _ _ _ _ crit _) crit)))

  (declare rc-flags (RuntimeConfig -> FeatureFlags))
  (define (rc-flags cfg)
    (match cfg ((RuntimeConfig _ _ _ _ _ flags) flags)))

  ;; ─── Defaults ───

  (declare default-connection-config (ConnectionConfig))
  (define default-connection-config
    (ConnectionConfig "http://localhost" 7474 ""))

  (declare default-ui-config (UiConfig))
  (define default-ui-config
    (UiConfig "dark" 5 False))

  (declare default-feature-flags (FeatureFlags))
  (define default-feature-flags
    (FeatureFlags True True True))

  (declare default-runtime-config (RuntimeConfig))
  (define default-runtime-config
    (RuntimeConfig default-connection-config
                   default-ui-config
                   5
                   250
                   1000
                   default-feature-flags))

  ;; ─── Merge helpers ───

  (declare pick-string (String -> String -> String))
  (define (pick-string base override)
    (if (== override "") base override))

  (declare pick-positive (Integer -> Integer -> Integer))
  (define (pick-positive base override)
    (if (> override 0) override base))

  (declare merge-connection-config (ConnectionConfig -> ConnectionConfig -> ConnectionConfig))
  (define (merge-connection-config base override)
    (ConnectionConfig
     (pick-string (cc-host base) (cc-host override))
     (pick-positive (cc-port base) (cc-port override))
     (pick-string (cc-token base) (cc-token override))))

  (declare merge-ui-config (UiConfig -> UiConfig -> UiConfig))
  (define (merge-ui-config base override)
    (UiConfig
     (pick-string (ui-theme base) (ui-theme override))
     (pick-positive (ui-refresh-seconds base) (ui-refresh-seconds override))
     (ui-compact-mode override)))

  (declare merge-feature-flags (FeatureFlags -> FeatureFlags -> FeatureFlags))
  (define (merge-feature-flags _base override)
    ;; booleans are explicit in overrides
    override)

  (declare merge-runtime-config (RuntimeConfig -> RuntimeConfig -> RuntimeConfig))
  (define (merge-runtime-config base override)
    (RuntimeConfig
     (merge-connection-config (rc-connection base) (rc-connection override))
     (merge-ui-config (rc-ui base) (rc-ui override))
     (pick-positive (rc-polling-seconds base) (rc-polling-seconds override))
     (pick-positive (rc-budget-warning-cents base) (rc-budget-warning-cents override))
     (pick-positive (rc-budget-critical-cents base) (rc-budget-critical-cents override))
     (merge-feature-flags (rc-flags base) (rc-flags override))))

  ;; ─── Validation ───

  (declare valid-theme-p (String -> Boolean))
  (define (valid-theme-p theme)
    (or (== theme "dark")
        (== theme "light")))

  (declare validate-runtime-config (RuntimeConfig -> (List String)))
  (define (validate-runtime-config cfg)
    (let ((conn (rc-connection cfg))
          (ui (rc-ui cfg))
          (polling (rc-polling-seconds cfg))
          (warn (rc-budget-warning-cents cfg))
          (crit (rc-budget-critical-cents cfg)))
      (append
       (if (== (cc-host conn) "")
           (Cons "connection.host is required" Nil)
           Nil)
       (append
        (if (<= (cc-port conn) 0)
            (Cons "connection.port must be > 0" Nil)
            Nil)
        (append
         (if (not (valid-theme-p (ui-theme ui)))
             (Cons "ui.theme must be one of: dark, light" Nil)
             Nil)
         (append
          (if (<= (ui-refresh-seconds ui) 0)
              (Cons "ui.refresh-seconds must be > 0" Nil)
              Nil)
          (append
           (if (or (<= polling 0) (> polling 3600))
               (Cons "polling-seconds must be within [1,3600]" Nil)
               Nil)
           (append
            (if (<= warn 0)
                (Cons "budget-warning-cents must be > 0" Nil)
                Nil)
            (append
             (if (<= crit 0)
                 (Cons "budget-critical-cents must be > 0" Nil)
                 Nil)
             (if (< crit warn)
                 (Cons "budget-critical-cents must be >= budget-warning-cents" Nil)
                 Nil))))))))))

  (declare config-valid-p (RuntimeConfig -> Boolean))
  (define (config-valid-p cfg)
    (match (validate-runtime-config cfg)
      ((Nil) True)
      (_ False)))

  (declare config-error-count (RuntimeConfig -> Integer))
  (define (config-error-count cfg)
    (fold (fn (acc _x) (+ acc 1)) 0 (validate-runtime-config cfg)))

  (declare config-first-error (RuntimeConfig -> String))
  (define (config-first-error cfg)
    (match (validate-runtime-config cfg)
      ((Nil) "")
      ((Cons e _) e))))

;;; ─── CL bridge ───

(cl:defun cl-default-runtime-config ()
  (coalton:coalton default-runtime-config))

(cl:defun cl-make-runtime-config (host port token theme ui-refresh compact-mode
                                       polling-seconds budget-warning-cents budget-critical-cents
                                       web-enabled tui-enabled mcclim-enabled)
  (coalton:coalton
   (RuntimeConfig
    (ConnectionConfig
     (lisp String () host)
     (lisp Integer () port)
     (lisp String () token))
    (UiConfig
     (lisp String () theme)
     (lisp Integer () ui-refresh)
     (lisp Boolean () compact-mode))
    (lisp Integer () polling-seconds)
    (lisp Integer () budget-warning-cents)
    (lisp Integer () budget-critical-cents)
    (FeatureFlags
     (lisp Boolean () web-enabled)
     (lisp Boolean () tui-enabled)
     (lisp Boolean () mcclim-enabled)))))

(cl:defun cl-merge-runtime-config (base override)
  (coalton:coalton
   (merge-runtime-config
    (lisp RuntimeConfig () base)
    (lisp RuntimeConfig () override))))

(cl:defun cl-config-valid-p (cfg)
  (coalton:coalton (config-valid-p (lisp RuntimeConfig () cfg))))

(cl:defun cl-config-error-count (cfg)
  (coalton:coalton (config-error-count (lisp RuntimeConfig () cfg))))

(cl:defun cl-config-first-error (cfg)
  (coalton:coalton (config-first-error (lisp RuntimeConfig () cfg))))

(cl:defun cl-config-host (cfg)
  (coalton:coalton (cc-host (rc-connection (lisp RuntimeConfig () cfg)))))

(cl:defun cl-config-port (cfg)
  (coalton:coalton (cc-port (rc-connection (lisp RuntimeConfig () cfg)))))

(cl:defun cl-config-theme (cfg)
  (coalton:coalton (ui-theme (rc-ui (lisp RuntimeConfig () cfg)))))

(cl:defun cl-config-polling-seconds (cfg)
  (coalton:coalton (rc-polling-seconds (lisp RuntimeConfig () cfg))))

(cl:defun cl-config-budget-warning-cents (cfg)
  (coalton:coalton (rc-budget-warning-cents (lisp RuntimeConfig () cfg))))

(cl:defun cl-config-budget-critical-cents (cfg)
  (coalton:coalton (rc-budget-critical-cents (lisp RuntimeConfig () cfg))))

(cl:defun cl-config-web-enabled-p (cfg)
  (coalton:coalton (ff-web-enabled (rc-flags (lisp RuntimeConfig () cfg)))))

(cl:defun cl-config-tui-enabled-p (cfg)
  (coalton:coalton (ff-tui-enabled (rc-flags (lisp RuntimeConfig () cfg)))))

(cl:defun cl-config-mcclim-enabled-p (cfg)
  (coalton:coalton (ff-mcclim-enabled (rc-flags (lisp RuntimeConfig () cfg)))))
