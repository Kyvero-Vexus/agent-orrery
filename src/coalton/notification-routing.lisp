;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; notification-routing.lisp — Coalton typed notification routing + dispatcher
;;;
;;; Bead: agent-orrery-78i

(in-package #:orrery/coalton/core)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  (define-type AlertSeverity
    SeverityInfo
    SeverityWarning
    SeverityCritical)

  (define-type AckLifecycle
    AckNone
    AckPending
    AckAcknowledged
    AckSnoozed)

  (define-type DeliveryChannel
    ChannelTuiOverlay
    ChannelWebToast
    ChannelMcclimPane)

  (define-type NotificationEvent
    (NotificationEvent String        ; id
                       AlertSeverity ; severity
                       String        ; title
                       String        ; source
                       Integer       ; fired-at
                       AckLifecycle))

  (define-type DispatcherConfig
    (DispatcherConfig Boolean  ; tui enabled
                      Boolean  ; web enabled
                      Boolean  ; mcclim enabled
                      Boolean  ; dedupe enabled
                      Integer)) ; ack threshold score

  (define-type RouteDecision
    (RouteDecision String               ; dedup key
                   (List DeliveryChannel) ; chosen channels
                   Boolean              ; suppressed duplicate?
                   Boolean              ; requires ack?
                   String))             ; reason

  ;; Accessors
  (declare ne-id (NotificationEvent -> String))
  (define (ne-id n)
    (match n ((NotificationEvent id _ _ _ _ _) id)))

  (declare ne-severity (NotificationEvent -> AlertSeverity))
  (define (ne-severity n)
    (match n ((NotificationEvent _ sev _ _ _ _) sev)))

  (declare ne-title (NotificationEvent -> String))
  (define (ne-title n)
    (match n ((NotificationEvent _ _ t _ _ _) t)))

  (declare ne-source (NotificationEvent -> String))
  (define (ne-source n)
    (match n ((NotificationEvent _ _ _ src _ _) src)))

  (declare ne-fired-at (NotificationEvent -> Integer))
  (define (ne-fired-at n)
    (match n ((NotificationEvent _ _ _ _ ts _) ts)))

  (declare ne-ack-state (NotificationEvent -> AckLifecycle))
  (define (ne-ack-state n)
    (match n ((NotificationEvent _ _ _ _ _ ack) ack)))

  (declare dc-tui-enabled (DispatcherConfig -> Boolean))
  (define (dc-tui-enabled c)
    (match c ((DispatcherConfig t _ _ _ _) t)))

  (declare dc-web-enabled (DispatcherConfig -> Boolean))
  (define (dc-web-enabled c)
    (match c ((DispatcherConfig _ w _ _ _) w)))

  (declare dc-mcclim-enabled (DispatcherConfig -> Boolean))
  (define (dc-mcclim-enabled c)
    (match c ((DispatcherConfig _ _ m _ _) m)))

  (declare dc-dedupe-enabled (DispatcherConfig -> Boolean))
  (define (dc-dedupe-enabled c)
    (match c ((DispatcherConfig _ _ _ d _) d)))

  (declare dc-ack-threshold (DispatcherConfig -> Integer))
  (define (dc-ack-threshold c)
    (match c ((DispatcherConfig _ _ _ _ t) t)))

  (declare rd-dedup-key (RouteDecision -> String))
  (define (rd-dedup-key d)
    (match d ((RouteDecision k _ _ _ _) k)))

  (declare rd-channels (RouteDecision -> (List DeliveryChannel)))
  (define (rd-channels d)
    (match d ((RouteDecision _ ch _ _ _) ch)))

  (declare rd-suppressed-duplicate-p (RouteDecision -> Boolean))
  (define (rd-suppressed-duplicate-p d)
    (match d ((RouteDecision _ _ s _ _) s)))

  (declare rd-requires-ack-p (RouteDecision -> Boolean))
  (define (rd-requires-ack-p d)
    (match d ((RouteDecision _ _ _ a _) a)))

  (declare rd-reason (RouteDecision -> String))
  (define (rd-reason d)
    (match d ((RouteDecision _ _ _ _ r) r)))

  ;; Defaults
  (declare default-dispatcher-config (DispatcherConfig))
  (define default-dispatcher-config
    (DispatcherConfig True True True True 80))

  ;; Severity helpers
  (declare severity-score (AlertSeverity -> Integer))
  (define (severity-score sev)
    (match sev
      ((SeverityInfo) 10)
      ((SeverityWarning) 60)
      ((SeverityCritical) 90)))

  (declare classify-severity (String -> AlertSeverity))
  (define (classify-severity s)
    (if (== s "critical")
        SeverityCritical
        (if (== s "warning")
            SeverityWarning
            SeverityInfo)))

  (declare severity-label (AlertSeverity -> String))
  (define (severity-label sev)
    (match sev
      ((SeverityInfo) "info")
      ((SeverityWarning) "warning")
      ((SeverityCritical) "critical")))

  (declare ack-label (AckLifecycle -> String))
  (define (ack-label ack)
    (match ack
      ((AckNone) "none")
      ((AckPending) "pending")
      ((AckAcknowledged) "acknowledged")
      ((AckSnoozed) "snoozed")))

  ;; Dedup key
  (declare event-dedup-key (NotificationEvent -> String))
  (define (event-dedup-key n)
    (mconcat (make-list (ne-source n) "|" (ne-title n) "|" (severity-label (ne-severity n)))))

  ;; List helpers
  (declare string-member-p (String -> (List String) -> Boolean))
  (define (string-member-p target items)
    (match items
      ((Nil) False)
      ((Cons x rest)
       (if (== x target)
           True
           (string-member-p target rest)))))

  (declare channel-label (DeliveryChannel -> String))
  (define (channel-label ch)
    (match ch
      ((ChannelTuiOverlay) "tui-overlay")
      ((ChannelWebToast) "web-toast")
      ((ChannelMcclimPane) "mcclim-pane")))

  (declare append-if (Boolean -> DeliveryChannel -> (List DeliveryChannel) -> (List DeliveryChannel)))
  (define (append-if cond channel acc)
    (if cond
        (append acc (make-list channel))
        acc))

  ;; Channel selection
  (declare choose-channels (DispatcherConfig -> AlertSeverity -> (List DeliveryChannel)))
  (define (choose-channels cfg sev)
    (let ((score (severity-score sev)))
      (let ((base Nil)
            (allow-tui (dc-tui-enabled cfg))
            (allow-web (dc-web-enabled cfg))
            (allow-mcclim (dc-mcclim-enabled cfg)))
        (if (< score 50)
            ;; info: TUI only
            (append-if allow-tui ChannelTuiOverlay base)
            (if (< score 80)
                ;; warning: TUI + Web
                (append-if allow-web ChannelWebToast
                           (append-if allow-tui ChannelTuiOverlay base))
                ;; critical: all enabled
                (append-if allow-mcclim ChannelMcclimPane
                           (append-if allow-web ChannelWebToast
                                      (append-if allow-tui ChannelTuiOverlay base))))))))

  ;; Dispatcher
  (declare dispatch-notification (NotificationEvent -> DispatcherConfig -> (List String) -> RouteDecision))
  (define (dispatch-notification event cfg seen-keys)
    (let ((key (event-dedup-key event))
          (score (severity-score (ne-severity event))))
      (let ((duplicate (if (dc-dedupe-enabled cfg)
                           (string-member-p key seen-keys)
                           False))
            (requires-ack (>= score (dc-ack-threshold cfg))))
        (if duplicate
            (RouteDecision key Nil True False "suppressed-duplicate")
            (RouteDecision key
                           (choose-channels cfg (ne-severity event))
                           False
                           requires-ack
                           "dispatched")))))

  ;; Batch dispatch (pure)
  (declare dispatch-batch ((List NotificationEvent) -> DispatcherConfig -> (List String) -> (List RouteDecision)))
  (define (dispatch-batch events cfg seen-keys)
    (match events
      ((Nil) Nil)
      ((Cons ev rest)
       (let ((decision (dispatch-notification ev cfg seen-keys)))
         (if (rd-suppressed-duplicate-p decision)
             (Cons decision (dispatch-batch rest cfg seen-keys))
             (Cons decision (dispatch-batch rest cfg
                                           (Cons (rd-dedup-key decision) seen-keys)))))))))

;;; ─── CL bridge ───

(cl:defun cl-severity-from-keyword (kw)
  (cl:ecase kw
    (:info (coalton:coalton SeverityInfo))
    (:warning (coalton:coalton SeverityWarning))
    (:critical (coalton:coalton SeverityCritical))))

(cl:defun cl-ack-from-keyword (kw)
  (cl:ecase kw
    (:none (coalton:coalton AckNone))
    (:pending (coalton:coalton AckPending))
    (:acknowledged (coalton:coalton AckAcknowledged))
    (:snoozed (coalton:coalton AckSnoozed))))

(cl:defun cl-default-dispatcher-config ()
  (coalton:coalton default-dispatcher-config))

(cl:defun cl-make-dispatcher-config (tui-enabled web-enabled mcclim-enabled dedupe-enabled ack-threshold)
  (coalton:coalton
   (DispatcherConfig
    (lisp Boolean () tui-enabled)
    (lisp Boolean () web-enabled)
    (lisp Boolean () mcclim-enabled)
    (lisp Boolean () dedupe-enabled)
    (lisp Integer () ack-threshold))))

(cl:defun cl-make-notification-event (id severity-kw title source fired-at ack-kw)
  (cl:let ((sev (cl-severity-from-keyword severity-kw))
           (ack (cl-ack-from-keyword ack-kw)))
    (coalton:coalton
     (NotificationEvent
      (lisp String () id)
      (lisp AlertSeverity () sev)
      (lisp String () title)
      (lisp String () source)
      (lisp Integer () fired-at)
      (lisp AckLifecycle () ack)))))

(cl:defun cl-%make-string-list (items)
  (cl:if (cl:null items)
      (coalton:coalton Nil)
      (cl:let ((hd (cl:car items))
               (tl (cl-%make-string-list (cl:cdr items))))
        (coalton:coalton
         (Cons
          (lisp String () hd)
          (lisp (List String) () tl))))))

(cl:defun cl-dispatch-notification (event cfg seen-keys)
  (cl:let ((seen (cl-%make-string-list seen-keys)))
    (coalton:coalton
     (dispatch-notification
      (lisp NotificationEvent () event)
      (lisp DispatcherConfig () cfg)
      (lisp (List String) () seen)))))

(cl:defun cl-route-dedup-key (decision)
  (coalton:coalton (rd-dedup-key (lisp RouteDecision () decision))))

(cl:defun cl-route-suppressed-p (decision)
  (coalton:coalton (rd-suppressed-duplicate-p (lisp RouteDecision () decision))))

(cl:defun cl-route-requires-ack-p (decision)
  (coalton:coalton (rd-requires-ack-p (lisp RouteDecision () decision))))

(cl:defun cl-route-reason (decision)
  (coalton:coalton (rd-reason (lisp RouteDecision () decision))))

(cl:defun cl-route-channel-keywords (decision)
  (cl:let ((labels (coalton:coalton
                    (map
                     channel-label
                     (rd-channels (lisp RouteDecision () decision))))))
    (cl:mapcar (cl:lambda (s)
                 (cl:intern (cl:string-upcase s) :keyword))
               labels)))
