;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; conformance.lisp — Typed plugin SDK conformance corpus + contract runner
;;;
;;; Bead: agent-orrery-bmc

(in-package #:orrery/plugin)

(deftype conformance-verdict ()
  '(member :pass :fail))

(defstruct (plugin-conformance-case (:conc-name pcc-))
  "Fixture for one conformance scenario."
  (case-id "" :type string)
  (plugin-name "" :type string)
  (plugin-version "1.0.0" :type string)
  (description "" :type string)
  (cards nil :type list)
  (commands nil :type list)
  (transformers nil :type list)
  (expected-valid-p t :type boolean)
  (expected-error-fragments nil :type list)
  (expected-warning-fragments nil :type list)
  (compat-tags nil :type list))

(defstruct (plugin-conformance-result (:conc-name pcr-))
  "Result for one conformance case."
  (case-id "" :type string)
  (verdict :pass :type conformance-verdict)
  (actual-valid-p t :type boolean)
  (errors nil :type list)
  (warnings nil :type list)
  (compat-findings nil :type list)
  (summary "" :type string))

(defstruct (plugin-conformance-report (:conc-name pcrep-))
  "Deterministic report for corpus execution."
  (suite-id "plugin-sdk-v1" :type string)
  (seed 0 :type fixnum)
  (generated-at 0 :type integer)
  (total 0 :type fixnum)
  (passed 0 :type fixnum)
  (failed 0 :type fixnum)
  (results nil :type list))

(defclass conformance-plugin (plugin)
  ((cards :initarg :cards :reader cp-cards :initform nil :type list)
   (commands :initarg :commands :reader cp-commands :initform nil :type list)
   (transformers :initarg :transformers :reader cp-transformers :initform nil :type list)))

(defmethod plugin-card-definitions ((p conformance-plugin))
  (cp-cards p))

(defmethod plugin-command-definitions ((p conformance-plugin))
  (cp-commands p))

(defmethod plugin-transformer-definitions ((p conformance-plugin))
  (cp-transformers p))

(declaim (ftype (function (plugin-conformance-case) (values list &optional))
                strict-schema-checks)
         (ftype (function (plugin-conformance-case) (values list &optional))
                compatibility-checks)
         (ftype (function (plugin-conformance-case) (values plugin-validation-result &optional))
                run-plugin-contract)
         (ftype (function (plugin-conformance-case) (values plugin-conformance-result &optional))
                run-conformance-case)
         (ftype (function (&key (:seed fixnum)) (values list &optional))
                make-default-plugin-conformance-corpus)
         (ftype (function (list &key (:seed fixnum) (:generated-at integer))
                          (values plugin-conformance-report &optional))
                run-plugin-conformance-corpus)
         (ftype (function (plugin-conformance-result) (values string &optional))
                conformance-result->json)
         (ftype (function (plugin-conformance-report) (values string &optional))
                conformance-report->json)
         (ftype (function () (values string &optional))
                deterministic-conformance-command))

(defun %contains-fragment-p (fragment strings)
  (declare (type string fragment) (type list strings))
  (some (lambda (s)
          (and (stringp s)
               (not (null (search (string-downcase fragment)
                                  (string-downcase s))))))
        strings))

(defun %all-fragments-present-p (fragments strings)
  (declare (type list fragments strings))
  (every (lambda (frag)
           (and (stringp frag)
                (%contains-fragment-p frag strings)))
         fragments))

(defun %duplicate-names (names)
  (declare (type list names))
  (let ((seen (make-hash-table :test #'equal))
        (dups nil))
    (dolist (name names)
      (when (and (stringp name) (> (length name) 0))
        (if (gethash name seen)
            (pushnew name dups :test #'string=)
            (setf (gethash name seen) t))))
    (nreverse dups)))

(defun strict-schema-checks (case)
  "Extra strict checks over fixture semantics (pure, deterministic)."
  (declare (type plugin-conformance-case case)
           (optimize (safety 3)))
  (let ((errors nil)
        (card-names nil)
        (cmd-names nil)
        (xf-names nil))
    (when (string= "" (pcc-plugin-name case))
      (push "Plugin name is required" errors))

    (dolist (card (pcc-cards case))
      (push (cd-name card) card-names)
      (unless (and (typep (cd-priority card) 'fixnum)
                   (<= 0 (cd-priority card) 100))
        (push (format nil "Card ~A priority out of range [0,100]" (cd-name card)) errors))
      (when (string= "" (cd-title card))
        (push (format nil "Card ~A title is required" (cd-name card)) errors)))

    (dolist (cmd (pcc-commands case))
      (push (cmd-name cmd) cmd-names)
      (when (string= "" (cmd-description cmd))
        (push (format nil "Command ~A description is required" (cmd-name cmd)) errors)))

    (dolist (xf (pcc-transformers case))
      (push (td-name xf) xf-names)
      (when (eq (td-input-type xf) (td-output-type xf))
        (push (format nil "Transformer ~A input/output types should differ for contract tests"
                      (td-name xf))
              errors)))

    (dolist (dup (%duplicate-names card-names))
      (push (format nil "Duplicate card name: ~A" dup) errors))
    (dolist (dup (%duplicate-names cmd-names))
      (push (format nil "Duplicate command name: ~A" dup) errors))
    (dolist (dup (%duplicate-names xf-names))
      (push (format nil "Duplicate transformer name: ~A" dup) errors))

    (nreverse errors)))

(defun compatibility-checks (case)
  "Compatibility findings for future SDK evolution.
Tags are warnings, not hard failures."
  (declare (type plugin-conformance-case case)
           (optimize (safety 3)))
  (let ((findings nil))
    (dolist (xf (pcc-transformers case))
      (unless (member (td-input-type xf) '(:any :usage :session :event :alert) :test #'eq)
        (push (format nil "Transformer ~A uses non-standard input type ~A"
                      (td-name xf) (td-input-type xf))
              findings))
      (unless (member (td-output-type xf) '(:any :usage :session :event :alert :json :text)
                      :test #'eq)
        (push (format nil "Transformer ~A uses non-standard output type ~A"
                      (td-name xf) (td-output-type xf))
              findings)))
    (dolist (tag (pcc-compat-tags case))
      (push (format nil "Compatibility tag: ~A" tag) findings))
    (nreverse findings)))

(defun run-plugin-contract (case)
  "Run base SDK contract validation against synthetic plugin instance."
  (declare (type plugin-conformance-case case)
           (optimize (safety 3)))
  (let ((plugin-instance (make-instance 'conformance-plugin
                                        :name (pcc-plugin-name case)
                                        :version (pcc-plugin-version case)
                                        :description (pcc-description case)
                                        :cards (pcc-cards case)
                                        :commands (pcc-commands case)
                                        :transformers (pcc-transformers case))))
    (validate-plugin plugin-instance)))

(defun run-conformance-case (case)
  "Execute one conformance case and compare with expected verdict."
  (declare (type plugin-conformance-case case)
           (optimize (safety 3)))
  (let* ((base-result (run-plugin-contract case))
         (strict-errors (strict-schema-checks case))
         (compat-findings (compatibility-checks case))
         (all-errors (append (pvr-errors base-result) strict-errors))
         (all-warnings (append (pvr-warnings base-result) compat-findings))
         (actual-valid (null all-errors))
         (expect-valid (pcc-expected-valid-p case))
         (errors-match (%all-fragments-present-p (pcc-expected-error-fragments case) all-errors))
         (warnings-match (%all-fragments-present-p (pcc-expected-warning-fragments case) all-warnings))
         (verdict (if (and (eq actual-valid expect-valid) errors-match warnings-match)
                      :pass
                      :fail)))
    (make-plugin-conformance-result
     :case-id (pcc-case-id case)
     :verdict verdict
     :actual-valid-p actual-valid
     :errors all-errors
     :warnings all-warnings
     :compat-findings compat-findings
     :summary (format nil "case=~A expected-valid=~A actual-valid=~A errors=~D warnings=~D"
                      (pcc-case-id case)
                      expect-valid
                      actual-valid
                      (length all-errors)
                      (length all-warnings)))))

(defun make-default-plugin-conformance-corpus (&key (seed 0))
  "Deterministic baseline corpus for Epic-6/7 gates."
  (declare (ignore seed)
           (optimize (safety 3)))
  (list
   ;; Positive baseline
   (make-plugin-conformance-case
    :case-id "plugin-sdk-positive-v1"
    :plugin-name "sample.valid"
    :plugin-version "1.0.0"
    :description "Valid card+command+transformer set"
    :cards (list (make-card-definition :name "ops-cost" :title "Ops Cost"
                                       :renderer (lambda (data stream)
                                                   (declare (ignore data))
                                                   (write-string "ok" stream))
                                       :data-fn (lambda () 1)
                                       :priority 10))
    :commands (list (make-command-definition :name "refresh"
                                             :handler (lambda (&rest args)
                                                        (declare (ignore args))
                                                        t)
                                             :description "Refresh dashboard"
                                             :keystroke #\r))
    :transformers (list (make-transformer-definition :name "usage->json"
                                                     :input-type :usage
                                                     :output-type :json
                                                     :transform-fn (lambda (x) x)))
    :expected-valid-p t)

   ;; Negative: missing command handler
   (make-plugin-conformance-case
    :case-id "plugin-sdk-negative-missing-handler"
    :plugin-name "sample.missing-handler"
    :plugin-version "1.0.0"
    :description "Invalid: command without handler"
    :commands (list (make-command-definition :name "broken"
                                             :handler nil
                                             :description "Broken command"))
    :expected-valid-p nil
    :expected-error-fragments (list "has no handler"))

   ;; Negative: duplicate command names + bad card priority
   (make-plugin-conformance-case
    :case-id "plugin-sdk-negative-duplicates"
    :plugin-name "sample.duplicates"
    :plugin-version "1.0.0"
    :description "Invalid: duplicate command names and card priority"
    :cards (list (make-card-definition :name "dup-card" :title "Dup"
                                       :renderer (lambda (d s) (declare (ignore d)) (write-string "x" s))
                                       :priority 101))
    :commands (list (make-command-definition :name "dup"
                                             :handler (lambda () t)
                                             :description "first")
                    (make-command-definition :name "dup"
                                             :handler (lambda () t)
                                             :description "second"))
    :expected-valid-p nil
    :expected-error-fragments (list "Duplicate command name" "priority out of range"))

   ;; Compatibility: non-standard transformer types should warn only
   (make-plugin-conformance-case
    :case-id "plugin-sdk-compat-nonstandard-types"
    :plugin-name "sample.compat"
    :plugin-version "1.1.0"
    :description "Compatibility warnings for non-standard transformer type labels"
    :cards (list (make-card-definition :name "compat-card" :title "Compat"
                                       :renderer (lambda (d s) (declare (ignore d)) (write-string "ok" s))
                                       :priority 30))
    :commands (list (make-command-definition :name "compat-cmd"
                                             :handler (lambda () t)
                                             :description "Compat cmd"))
    :transformers (list (make-transformer-definition :name "typed-xf"
                                                     :input-type :vendor-x
                                                     :output-type :vendor-y
                                                     :transform-fn (lambda (x) x)))
    :expected-valid-p t
    :expected-warning-fragments (list "non-standard input type" "non-standard output type")
    :compat-tags (list :forward-compat :vendor-extension))))

(defun run-plugin-conformance-corpus (corpus &key (seed 0) (generated-at 0))
  "Run full corpus deterministically and return typed report."
  (declare (type list corpus)
           (type fixnum seed)
           (type integer generated-at)
           (optimize (safety 3)))
  (let ((results nil)
        (passed 0)
        (failed 0))
    (dolist (case corpus)
      (let ((result (run-conformance-case case)))
        (push result results)
        (if (eq :pass (pcr-verdict result))
            (incf passed)
            (incf failed))))
    (make-plugin-conformance-report
     :suite-id "plugin-sdk-v1"
     :seed seed
     :generated-at generated-at
     :total (+ passed failed)
     :passed passed
     :failed failed
     :results (nreverse results))))

(defun deterministic-conformance-command ()
  "Deterministic invocation for docs + release gates."
  (declare (optimize (safety 3)))
  "export LD_LIBRARY_PATH=\"/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH\" && sbcl --eval '(load \"/home/slime/quicklisp/setup.lisp\")' --script ci/run-tests.lisp")

(defun conformance-result->json (result)
  "Serialize one result to deterministic JSON."
  (declare (type plugin-conformance-result result)
           (optimize (safety 3)))
  (format nil "{\"case_id\":\"~A\",\"verdict\":\"~A\",\"actual_valid\":~A,\"errors\":~D,\"warnings\":~D}"
          (pcr-case-id result)
          (string-downcase (symbol-name (pcr-verdict result)))
          (if (pcr-actual-valid-p result) "true" "false")
          (length (pcr-errors result))
          (length (pcr-warnings result))))

(defun conformance-report->json (report)
  "Serialize report to deterministic JSON."
  (declare (type plugin-conformance-report report)
           (optimize (safety 3)))
  (format nil
          "{\"suite\":\"~A\",\"seed\":~D,\"generated_at\":~D,\"total\":~D,\"passed\":~D,\"failed\":~D,\"results\":[~{~A~^,~}]}"
          (pcrep-suite-id report)
          (pcrep-seed report)
          (pcrep-generated-at report)
          (pcrep-total report)
          (pcrep-passed report)
          (pcrep-failed report)
          (mapcar #'conformance-result->json (pcrep-results report))))
