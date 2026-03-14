;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capability-matrix.lisp — Typed interface capability matrix generator
;;;
;;; Derives TUI/Web/McCLIM kickoff checklists from normalized adapter
;;; outputs once Epic 2 gate is resolved, producing deterministic
;;; per-interface work packets and shared contract fixtures.

(in-package #:orrery/adapter)

;;; ─── Interface Target ───

(deftype interface-target ()
  '(member :tui :web :mcclim))

;;; ─── Capability Requirement ───

(defstruct (cap-requirement
             (:constructor make-cap-requirement
                 (&key name interface criticality description))
             (:conc-name creq-))
  "A single capability requirement for an interface."
  (name "" :type string)
  (interface :tui :type interface-target)
  (criticality :required :type (member :required :recommended :optional))
  (description "" :type string))

;;; ─── Capability Status Entry ───

(deftype cap-status ()
  '(member :available :degraded :missing :untested))

(defstruct (cap-status-entry
             (:constructor make-cap-status-entry
                 (&key requirement status evidence remediation))
             (:conc-name cse-))
  "Status of a single capability requirement after evaluation."
  (requirement (make-cap-requirement) :type cap-requirement)
  (status :untested :type cap-status)
  (evidence "" :type string)
  (remediation "" :type string))

;;; ─── Kickoff Checklist ───

(deftype kickoff-readiness ()
  '(member :go :conditional :no-go))

(defstruct (kickoff-checklist
             (:constructor make-kickoff-checklist
                 (&key interface readiness entries
                       required-met required-total
                       recommended-met recommended-total
                       summary))
             (:conc-name kc-))
  "Complete kickoff checklist for one interface."
  (interface :tui :type interface-target)
  (readiness :no-go :type kickoff-readiness)
  (entries '() :type list)
  (required-met 0 :type fixnum)
  (required-total 0 :type fixnum)
  (recommended-met 0 :type fixnum)
  (recommended-total 0 :type fixnum)
  (summary "" :type string))

;;; ─── Contract Fixture ───

(defstruct (shared-fixture
             (:constructor make-shared-fixture
                 (&key fixture-id capabilities endpoint-map timestamp))
             (:conc-name sf-))
  "Shared contract fixture for cross-interface testing."
  (fixture-id "" :type string)
  (capabilities '() :type list)
  (endpoint-map '() :type list)   ; alist of (endpoint-name . fixture-response)
  (timestamp 0 :type integer))

;;; ─── Capability Matrix ───

(defstruct (capability-matrix
             (:constructor make-capability-matrix
                 (&key gate-decision checklists shared-fixtures
                       overall-readiness timestamp))
             (:conc-name cxm-))
  "Complete capability matrix spanning all interfaces."
  (gate-decision :pass :type gate-outcome)
  (checklists '() :type list)
  (shared-fixtures '() :type list)
  (overall-readiness :no-go :type kickoff-readiness)
  (timestamp 0 :type integer))

;;; ─── Interface Capability Requirements ───

(defparameter *tui-requirements*
  (list (make-cap-requirement :name "health" :interface :tui
                              :criticality :required
                              :description "System health endpoint for dashboard status")
        (make-cap-requirement :name "sessions-list" :interface :tui
                              :criticality :required
                              :description "Session listing for keyboard-first navigation")
        (make-cap-requirement :name "session-history" :interface :tui
                              :criticality :required
                              :description "Message history for session drill-down")
        (make-cap-requirement :name "list-cron" :interface :tui
                              :criticality :required
                              :description "Cron job listing for operations panel")
        (make-cap-requirement :name "tail-events" :interface :tui
                              :criticality :recommended
                              :description "Event stream for live activity feed")
        (make-cap-requirement :name "list-alerts" :interface :tui
                              :criticality :recommended
                              :description "Alert listing for notification panel")
        (make-cap-requirement :name "usage-records" :interface :tui
                              :criticality :optional
                              :description "Usage/cost data for cost dashboard"))
  "Capability requirements for Epic 3 (TUI).")

(defparameter *web-requirements*
  (list (make-cap-requirement :name "health" :interface :web
                              :criticality :required
                              :description "System health for browser dashboard")
        (make-cap-requirement :name "sessions-list" :interface :web
                              :criticality :required
                              :description "Session listing for web table view")
        (make-cap-requirement :name "system-status" :interface :web
                              :criticality :required
                              :description "System status aggregate for overview page")
        (make-cap-requirement :name "usage-records" :interface :web
                              :criticality :required
                              :description "Usage data for cost analytics")
        (make-cap-requirement :name "tail-events" :interface :web
                              :criticality :recommended
                              :description "Event stream for live update panel")
        (make-cap-requirement :name "list-alerts" :interface :web
                              :criticality :recommended
                              :description "Alert listing for notification center"))
  "Capability requirements for Epic 4 (Web).")

(defparameter *mcclim-requirements*
  (list (make-cap-requirement :name "health" :interface :mcclim
                              :criticality :required
                              :description "System health for McCLIM inspector")
        (make-cap-requirement :name "sessions-list" :interface :mcclim
                              :criticality :required
                              :description "Session listing for CLIM presentation")
        (make-cap-requirement :name "session-history" :interface :mcclim
                              :criticality :recommended
                              :description "Message history for conversation inspector")
        (make-cap-requirement :name "list-subagents" :interface :mcclim
                              :criticality :recommended
                              :description "Subagent tree for hierarchy viewer")
        (make-cap-requirement :name "list-cron" :interface :mcclim
                              :criticality :optional
                              :description "Cron jobs for command workflow"))
  "Capability requirements for Epic 5 (McCLIM).")

;;; ─── Evaluation Engine ───

(declaim (ftype (function (cap-requirement harness-result (or null drift-report))
                          (values cap-status-entry &optional))
                evaluate-requirement)
         (ftype (function (interface-target list harness-result list)
                          (values kickoff-checklist &optional))
                build-checklist)
         (ftype (function (gate-decision-record harness-result list)
                          (values capability-matrix &optional))
                generate-capability-matrix)
         (ftype (function (capability-matrix) (values string &optional))
                capability-matrix-to-json))

(defun evaluate-requirement (req harness drift-report)
  "Evaluate a single capability requirement against harness + drift data."
  (declare (type cap-requirement req)
           (type harness-result harness)
           (type (or null drift-report) drift-report))
  (let* ((name (creq-name req))
         (check (find name (chr-checks harness)
                      :key #'cc-endpoint-name
                      :test (lambda (c ep) (search c ep :test #'char-equal)))))
    (cond
      ;; Not tested at all
      ((null check)
       (make-cap-status-entry
        :requirement req :status :missing
        :evidence "No contract check found"
        :remediation (format nil "Add contract check for ~A" name)))
      ;; Contract check passed
      ((eq :pass (cc-verdict check))
       (let ((drift-ok (or (null drift-report)
                           (dr-compatible-p drift-report))))
         (if drift-ok
             (make-cap-status-entry
              :requirement req :status :available
              :evidence (format nil "Contract pass: ~A" (cc-message check))
              :remediation "")
             (make-cap-status-entry
              :requirement req :status :degraded
              :evidence (format nil "Contract pass but drift detected: ~A"
                                (cc-message check))
              :remediation "Investigate schema drift for long-term stability"))))
      ;; Contract check skipped
      ((eq :skip (cc-verdict check))
       (make-cap-status-entry
        :requirement req :status :untested
        :evidence (format nil "Skipped: ~A" (cc-message check))
        :remediation "Enable and run contract check"))
      ;; Contract check failed
      (t
       (make-cap-status-entry
        :requirement req :status :missing
        :evidence (format nil "Contract fail: ~A" (cc-message check))
        :remediation (format nil "Fix ~A contract failure" name))))))

(defun %count-by-criticality-and-status (entries criticality available-statuses)
  "Count entries matching criticality with status in available-statuses."
  (declare (type list entries available-statuses) (type keyword criticality))
  (count-if (lambda (e)
              (and (eq criticality (creq-criticality (cse-requirement e)))
                   (member (cse-status e) available-statuses)))
            entries))

(defun build-checklist (interface requirements harness drift-reports)
  "Build a kickoff checklist for one interface."
  (declare (type interface-target interface)
           (type list requirements drift-reports)
           (type harness-result harness))
  (let* ((entries (mapcar (lambda (req)
                            (let ((drift (find (creq-name req) drift-reports
                                               :key #'dr-endpoint-name
                                               :test (lambda (c ep)
                                                       (search c ep :test #'char-equal)))))
                              (evaluate-requirement req harness drift)))
                          requirements))
         (req-total (count :required requirements :key #'creq-criticality))
         (req-met (%count-by-criticality-and-status
                   entries :required '(:available :degraded)))
         (rec-total (count :recommended requirements :key #'creq-criticality))
         (rec-met (%count-by-criticality-and-status
                   entries :recommended '(:available :degraded)))
         (readiness (cond
                      ((= req-met req-total)
                       (if (= rec-met rec-total) :go :conditional))
                      (t :no-go))))
    (make-kickoff-checklist
     :interface interface
     :readiness readiness
     :entries entries
     :required-met req-met :required-total req-total
     :recommended-met rec-met :recommended-total rec-total
     :summary (format nil "~A: ~A (~D/~D required, ~D/~D recommended)"
                      (string-downcase (symbol-name interface))
                      (string-downcase (symbol-name readiness))
                      req-met req-total rec-met rec-total))))

(defun %build-shared-fixture (harness)
  "Build a shared contract fixture from harness results."
  (declare (type harness-result harness))
  (let ((endpoints '()))
    (dolist (check (chr-checks harness))
      (when (eq :pass (cc-verdict check))
        (push (cons (cc-endpoint-name check)
                    (format nil "fixture:~A" (cc-endpoint-name check)))
              endpoints)))
    (make-shared-fixture
     :fixture-id (format nil "fixture-~A" (get-universal-time))
     :capabilities (mapcar #'car endpoints)
     :endpoint-map (nreverse endpoints)
     :timestamp (get-universal-time))))

(defun generate-capability-matrix (decision harness drift-reports)
  "Generate complete capability matrix from gate decision + harness + drift data."
  (declare (type gate-decision-record decision)
           (type harness-result harness)
           (type list drift-reports))
  (let* ((tui-cl (build-checklist :tui *tui-requirements* harness drift-reports))
         (web-cl (build-checklist :web *web-requirements* harness drift-reports))
         (mcclim-cl (build-checklist :mcclim *mcclim-requirements* harness drift-reports))
         (checklists (list tui-cl web-cl mcclim-cl))
         (overall (cond
                    ((every (lambda (c) (eq :go (kc-readiness c))) checklists) :go)
                    ((every (lambda (c) (member (kc-readiness c) '(:go :conditional)))
                            checklists) :conditional)
                    (t :no-go)))
         (fixture (%build-shared-fixture harness)))
    (make-capability-matrix
     :gate-decision (gdr-outcome decision)
     :checklists checklists
     :shared-fixtures (list fixture)
     :overall-readiness overall
     :timestamp (get-universal-time))))

;;; ─── JSON Serialization ───

(defun %cap-status-entry-to-json (entry stream)
  "Serialize one cap-status-entry to JSON on stream."
  (declare (type cap-status-entry entry) (type stream stream))
  (let ((req (cse-requirement entry)))
    (write-string "{\"name\":" stream)
    (emit-json-string (creq-name req) stream)
    (write-string ",\"interface\":" stream)
    (emit-json-string (string-downcase (symbol-name (creq-interface req))) stream)
    (write-string ",\"criticality\":" stream)
    (emit-json-string (string-downcase (symbol-name (creq-criticality req))) stream)
    (write-string ",\"status\":" stream)
    (emit-json-string (string-downcase (symbol-name (cse-status entry))) stream)
    (write-string ",\"evidence\":" stream)
    (emit-json-string (cse-evidence entry) stream)
    (write-string ",\"remediation\":" stream)
    (emit-json-string (cse-remediation entry) stream)
    (write-string "}" stream)))

(defun capability-matrix-to-json (matrix)
  "Serialize capability matrix to deterministic JSON."
  (declare (type capability-matrix matrix))
  (with-output-to-string (s)
    (write-string "{" s)
    (write-string "\"gate_decision\":" s)
    (emit-json-string (string-downcase (symbol-name (cxm-gate-decision matrix))) s)
    (write-string ",\"overall_readiness\":" s)
    (emit-json-string (string-downcase (symbol-name (cxm-overall-readiness matrix))) s)
    (write-string ",\"timestamp\":" s)
    (format s "~D" (cxm-timestamp matrix))
    (write-string ",\"checklists\":[" s)
    (let ((first-cl t))
      (dolist (cl (cxm-checklists matrix))
        (unless first-cl (write-char #\, s))
        (setf first-cl nil)
        (write-string "{\"interface\":" s)
        (emit-json-string (string-downcase (symbol-name (kc-interface cl))) s)
        (write-string ",\"readiness\":" s)
        (emit-json-string (string-downcase (symbol-name (kc-readiness cl))) s)
        (write-string ",\"required_met\":" s)
        (format s "~D" (kc-required-met cl))
        (write-string ",\"required_total\":" s)
        (format s "~D" (kc-required-total cl))
        (write-string ",\"recommended_met\":" s)
        (format s "~D" (kc-recommended-met cl))
        (write-string ",\"recommended_total\":" s)
        (format s "~D" (kc-recommended-total cl))
        (write-string ",\"summary\":" s)
        (emit-json-string (kc-summary cl) s)
        (write-string ",\"entries\":[" s)
        (let ((first-e t))
          (dolist (e (kc-entries cl))
            (unless first-e (write-char #\, s))
            (setf first-e nil)
            (%cap-status-entry-to-json e s)))
        (write-string "]}" s)))
    (write-string "],\"shared_fixtures\":[" s)
    (let ((first-f t))
      (dolist (f (cxm-shared-fixtures matrix))
        (unless first-f (write-char #\, s))
        (setf first-f nil)
        (write-string "{\"fixture_id\":" s)
        (emit-json-string (sf-fixture-id f) s)
        (write-string ",\"capabilities\":[" s)
        (let ((first-c t))
          (dolist (c (sf-capabilities f))
            (unless first-c (write-char #\, s))
            (setf first-c nil)
            (emit-json-string c s)))
        (write-string "]}" s)))
    (write-string "]}" s)))
