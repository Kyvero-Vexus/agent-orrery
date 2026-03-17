;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; replay-protocol-bridge.lisp — Deterministic trace→typed UI protocol bridge
;;;
;;; Converts canonical runtime trace streams into typed UI protocol messages,
;;; then builds deterministic parity fixtures for Web/TUI/McCLIM replay checks.

(in-package #:orrery/adapter)

(deftype replay-surface ()
  '(member :web :tui :mcclim))

(defstruct (protocol-parity-row
             (:constructor make-protocol-parity-row
                 (&key sequence-id web-kind tui-kind mcclim-kind
                       web-hash tui-hash mcclim-hash parity-p detail))
             (:conc-name ppr-))
  "One deterministic parity row for replay fixture comparison."
  (sequence-id 0 :type (integer 0))
  (web-kind :status :type ui-message-kind)
  (tui-kind :status :type ui-message-kind)
  (mcclim-kind :status :type ui-message-kind)
  (web-hash 0 :type fixnum)
  (tui-hash 0 :type fixnum)
  (mcclim-hash 0 :type fixnum)
  (parity-p nil :type boolean)
  (detail "" :type string))

(defstruct (protocol-parity-fixture
             (:constructor make-protocol-parity-fixture
                 (&key fixture-id rows parity-pass-p stream-count row-count timestamp))
             (:conc-name ppf-))
  "Deterministic parity fixture compiled from trace replay streams."
  (fixture-id "" :type string)
  (rows '() :type list)
  (parity-pass-p nil :type boolean)
  (stream-count 0 :type (integer 0))
  (row-count 0 :type (integer 0))
  (timestamp 0 :type (integer 0)))

(declaim
 (ftype (function (event-kind) (values ui-message-kind &optional)) event-kind->ui-kind)
 (ftype (function (trace-event replay-surface) (values ui-message &optional)) trace-event->ui-message)
 (ftype (function (trace-stream replay-surface) (values list &optional)) trace-stream->ui-messages)
 (ftype (function (list list list &key (:fixture-id string) (:timestamp (integer 0)))
                  (values protocol-parity-fixture &optional))
        build-protocol-parity-fixture)
 (ftype (function (protocol-parity-fixture) (values string &optional))
        protocol-parity-fixture->json))

(defun event-kind->ui-kind (kind)
  "Map canonical trace event-kind to typed UI protocol kind."
  (declare (type event-kind kind))
  (ecase kind
    (:session :session)
    (:cron :cron)
    (:health :health)
    (:alert :alert)
    (:usage :analytics)
    (:probe :status)
    (:lifecycle :audit)))

(defun %payload-from-trace-event (event)
  (declare (type trace-event event))
  (list (cons :seq-id (tev-seq-id event))
        (cons :source (tev-source-tag event))
        (cons :payload-hash (tev-payload-hash event))))

(defun trace-event->ui-message (event surface)
  "Convert one canonical trace-event to typed UI protocol message."
  (declare (type trace-event event)
           (type replay-surface surface))
  (make-ui-message*
   surface
   (event-kind->ui-kind (tev-event-kind event))
   (tev-timestamp event)
   (tev-seq-id event)
   (%payload-from-trace-event event)))

(defun trace-stream->ui-messages (stream surface)
  "Convert a canonical trace-stream to deterministic typed UI protocol messages."
  (declare (type trace-stream stream)
           (type replay-surface surface))
  (loop for event in (ts-events stream)
        collect (trace-event->ui-message event surface)))

(defun %message-hash (msg)
  (declare (type ui-message msg))
  (let ((payload-hash (cdr (assoc :payload-hash (uim-payload msg) :test #'eq))))
    (logand (sxhash (list (uim-kind msg)
                          (uim-sequence msg)
                          (uim-timestamp msg)
                          payload-hash))
            most-positive-fixnum)))

(defun %message-at (messages seq-id)
  (find seq-id messages :key #'uim-sequence :test #'=))

(defun build-protocol-parity-fixture (web-messages tui-messages mcclim-messages
                                      &key (fixture-id "") (timestamp 0))
  "Build parity fixture rows from typed protocol streams for Web/TUI/McCLIM."
  (declare (type list web-messages tui-messages mcclim-messages)
           (type string fixture-id)
           (type (integer 0) timestamp))
  (let* ((seq-ids (sort (remove-duplicates
                         (append (mapcar #'uim-sequence web-messages)
                                 (mapcar #'uim-sequence tui-messages)
                                 (mapcar #'uim-sequence mcclim-messages))
                         :test #'=)
                        #'<))
         (rows '())
         (all-pass t))
    (dolist (seq-id seq-ids)
      (let* ((w (%message-at web-messages seq-id))
             (tu (%message-at tui-messages seq-id))
             (m (%message-at mcclim-messages seq-id))
             (wk (if w (uim-kind w) :status))
             (tk (if tu (uim-kind tu) :status))
             (mk (if m (uim-kind m) :status))
             (wh (if w (%message-hash w) -1))
             (th (if tu (%message-hash tu) -1))
             (mh (if m (%message-hash m) -1))
             (parity (and (eq wk tk) (eq tk mk)
                          (= wh th) (= th mh))))
        (unless parity (setf all-pass nil))
        (push (make-protocol-parity-row
               :sequence-id seq-id
               :web-kind wk
               :tui-kind tk
               :mcclim-kind mk
               :web-hash wh
               :tui-hash th
               :mcclim-hash mh
               :parity-p parity
               :detail (if parity "match" "mismatch"))
              rows)))
    (make-protocol-parity-fixture
     :fixture-id fixture-id
     :rows (nreverse rows)
     :parity-pass-p all-pass
     :stream-count 3
     :row-count (length seq-ids)
     :timestamp timestamp)))

(defun protocol-parity-fixture->json (fixture)
  "Serialize protocol-parity-fixture deterministically."
  (declare (type protocol-parity-fixture fixture))
  (with-output-to-string (s)
    (format s
            "{\"fixture_id\":\"~A\",\"parity_pass\":~A,\"stream_count\":~D,\"row_count\":~D,\"timestamp\":~D,\"rows\":["
            (ppf-fixture-id fixture)
            (if (ppf-parity-pass-p fixture) "true" "false")
            (ppf-stream-count fixture)
            (ppf-row-count fixture)
            (ppf-timestamp fixture))
    (loop for row in (ppf-rows fixture)
          for first = t then nil
          do (progn
               (unless first (write-char #\, s))
               (format s
                       "{\"sequence_id\":~D,\"web_kind\":\"~(~A~)\",\"tui_kind\":\"~(~A~)\",\"mcclim_kind\":\"~(~A~)\",\"parity\":~A,\"detail\":\"~A\"}"
                       (ppr-sequence-id row)
                       (ppr-web-kind row)
                       (ppr-tui-kind row)
                       (ppr-mcclim-kind row)
                       (if (ppr-parity-p row) "true" "false")
                       (ppr-detail row))))
    (write-string "]}" s)))
