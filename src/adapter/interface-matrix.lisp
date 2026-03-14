;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; interface-matrix.lisp — Interface capability matrix for Epic 3/4/5 kickoff
;;;
;;; Derives TUI/Web/McCLIM kickoff checklists from adapter outputs,
;;; producing per-interface work packets and shared contract fixtures.

(in-package #:orrery/adapter)

;;; ─── Interface Types ───

(deftype interface-kind ()
  '(member :tui :web :mcclim))

(deftype readiness-level ()
  '(member :ready :needs-adapter :needs-fixture :not-started))

;;; ─── Capability Requirement ───

(defstruct (interface-capability
             (:constructor make-interface-capability
                 (&key name interface required-p adapter-endpoint
                       fixture-available-p))
             (:conc-name ic-))
  "One capability required by an interface."
  (name "" :type string)
  (interface :tui :type interface-kind)
  (required-p t :type boolean)
  (adapter-endpoint "" :type string)
  (fixture-available-p nil :type boolean))

;;; ─── Work Packet ───

(defstruct (work-packet
             (:constructor make-work-packet
                 (&key interface-kind epic-id readiness
                       capabilities missing-capabilities
                       fixture-gaps kickoff-checklist))
             (:conc-name wp-))
  "Kickoff work packet for one interface."
  (interface-kind :tui :type interface-kind)
  (epic-id "" :type string)
  (readiness :not-started :type readiness-level)
  (capabilities '() :type list)
  (missing-capabilities '() :type list)
  (fixture-gaps '() :type list)
  (kickoff-checklist '() :type list))

;;; ─── Interface Matrix ───

(defstruct (interface-matrix
             (:constructor make-interface-matrix
                 (&key packets shared-fixtures
                       adapter-coverage-pct timestamp))
             (:conc-name im-))
  "Complete interface capability matrix."
  (packets '() :type list)
  (shared-fixtures '() :type list)
  (adapter-coverage-pct 0 :type fixnum)
  (timestamp 0 :type integer))

;;; ─── Standard Requirements ───

(defparameter *tui-requirements*
  (list (make-interface-capability
         :name "session-list" :interface :tui :required-p t
         :adapter-endpoint "sessions-list")
        (make-interface-capability
         :name "session-history" :interface :tui :required-p t
         :adapter-endpoint "session-history")
        (make-interface-capability
         :name "health-check" :interface :tui :required-p t
         :adapter-endpoint "health")
        (make-interface-capability
         :name "send-message" :interface :tui :required-p nil
         :adapter-endpoint "session-send")))

(defparameter *web-requirements*
  (list (make-interface-capability
         :name "session-list" :interface :web :required-p t
         :adapter-endpoint "sessions-list")
        (make-interface-capability
         :name "session-history" :interface :web :required-p t
         :adapter-endpoint "session-history")
        (make-interface-capability
         :name "health-check" :interface :web :required-p t
         :adapter-endpoint "health")
        (make-interface-capability
         :name "system-status" :interface :web :required-p nil
         :adapter-endpoint "system-status")))

(defparameter *mcclim-requirements*
  (list (make-interface-capability
         :name "session-list" :interface :mcclim :required-p t
         :adapter-endpoint "sessions-list")
        (make-interface-capability
         :name "health-check" :interface :mcclim :required-p t
         :adapter-endpoint "health")))

;;; ─── Matrix Generator ───

(declaim (ftype (function (conformance-matrix) (values interface-matrix &optional))
                generate-interface-matrix)
         (ftype (function (interface-matrix) (values string &optional))
                interface-matrix-to-json))

(defun %check-interface-caps (conformance-matrix caps epic-id)
  "Build work packet for one interface."
  (declare (type conformance-matrix conformance-matrix)
           (type list caps) (type string epic-id))
  (let ((missing '())
        (fixture-gaps '())
        (checklist '()))
    (dolist (cap caps)
      ;; Check adapter coverage
      (let ((entry (find (ic-adapter-endpoint cap)
                         (cm-entries conformance-matrix)
                         :key #'ce-endpoint-name
                         :test (lambda (ep name) (search ep name :test #'char-equal)))))
        (cond
          ((or (null entry)
               (member (ce-coverage entry) '(:missing :stub)))
           (when (ic-required-p cap)
             (push (ic-name cap) missing))
           (push (format nil "Capture fixture for ~A endpoint" (ic-adapter-endpoint cap))
                 fixture-gaps)
           (push (format nil "[ ] Implement ~A adapter integration" (ic-name cap))
                 checklist))
          (t
           (setf (ic-fixture-available-p cap) t)
           (push (format nil "[x] ~A adapter integration ready" (ic-name cap))
                 checklist)))))
    (let ((readiness (cond
                       (missing :needs-adapter)
                       (fixture-gaps :needs-fixture)
                       (t :ready))))
      (make-work-packet
       :interface-kind (ic-interface (first caps))
       :epic-id epic-id
       :readiness readiness
       :capabilities caps
       :missing-capabilities (nreverse missing)
       :fixture-gaps (nreverse fixture-gaps)
       :kickoff-checklist (nreverse checklist)))))

(defun generate-interface-matrix (conformance-matrix)
  "Generate interface capability matrix from adapter conformance state."
  (declare (type conformance-matrix conformance-matrix))
  (let* ((tui-packet (%check-interface-caps
                      conformance-matrix *tui-requirements* "epic-3"))
         (web-packet (%check-interface-caps
                      conformance-matrix *web-requirements* "epic-4"))
         (mcclim-packet (%check-interface-caps
                         conformance-matrix *mcclim-requirements* "epic-5"))
         (packets (list tui-packet web-packet mcclim-packet))
         ;; Shared fixtures: endpoints referenced by multiple interfaces
         (all-endpoints (remove-duplicates
                         (mapcan (lambda (p)
                                   (mapcar #'ic-adapter-endpoint
                                           (wp-capabilities p)))
                                 packets)
                         :test #'string=))
         ;; Coverage percentage
         (total (length (cm-entries conformance-matrix)))
         (covered (count :full (cm-entries conformance-matrix)
                         :key #'ce-coverage)))
    (make-interface-matrix
     :packets packets
     :shared-fixtures all-endpoints
     :adapter-coverage-pct (if (zerop total) 0
                               (round (* 100 covered) total))
     :timestamp (get-universal-time))))

;;; ─── JSON Serialization ───

(defun interface-matrix-to-json (matrix)
  "Serialize interface matrix to deterministic JSON."
  (declare (type interface-matrix matrix))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"adapter_coverage_pct\":" s)
    (format s "~D" (im-adapter-coverage-pct matrix))
    (write-string ",\"timestamp\":" s)
    (format s "~D" (im-timestamp matrix))
    (write-string ",\"shared_fixtures\":[" s)
    (let ((first t))
      (dolist (f (im-shared-fixtures matrix))
        (unless first (write-char #\, s))
        (setf first nil)
        (emit-json-string f s)))
    (write-string "],\"packets\":[" s)
    (let ((first t))
      (dolist (p (im-packets matrix))
        (unless first (write-char #\, s))
        (setf first nil)
        (write-string "{\"interface\":" s)
        (emit-json-string (string-downcase (symbol-name (wp-interface-kind p))) s)
        (write-string ",\"epic_id\":" s)
        (emit-json-string (wp-epic-id p) s)
        (write-string ",\"readiness\":" s)
        (emit-json-string (string-downcase (symbol-name (wp-readiness p))) s)
        (write-string ",\"missing\":[" s)
        (let ((first-m t))
          (dolist (m (wp-missing-capabilities p))
            (unless first-m (write-char #\, s))
            (setf first-m nil)
            (emit-json-string m s)))
        (write-string "],\"fixture_gaps\":[" s)
        (let ((first-g t))
          (dolist (g (wp-fixture-gaps p))
            (unless first-g (write-char #\, s))
            (setf first-g nil)
            (emit-json-string g s)))
        (write-string "],\"checklist\":[" s)
        (let ((first-c t))
          (dolist (c (wp-kickoff-checklist p))
            (unless first-c (write-char #\, s))
            (setf first-c nil)
            (emit-json-string c s)))
        (write-string "]}" s)))
    (write-string "]}" s)))
