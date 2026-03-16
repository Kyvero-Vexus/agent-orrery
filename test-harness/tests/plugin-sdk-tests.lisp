;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; plugin-sdk-tests.lisp — Tests for plugin SDK
;;; Bead: agent-orrery-eb0.6.1

(in-package #:orrery/harness-tests)

;;; Test plugin
(defclass test-plugin (orrery/plugin:plugin) ())

(defmethod orrery/plugin:plugin-card-definitions ((p test-plugin))
  (list (orrery/plugin:make-card-definition
         :name "test-card" :title "Test Card"
         :renderer (lambda (data stream) (declare (ignore data)) (write-string "test" stream))
         :data-fn (lambda () 42)
         :priority 10)))

(defmethod orrery/plugin:plugin-command-definitions ((p test-plugin))
  (list (orrery/plugin:make-command-definition
         :name "test-cmd" :handler (lambda () t) :description "A test command")))

(defmethod orrery/plugin:plugin-transformer-definitions ((p test-plugin))
  (list (orrery/plugin:make-transformer-definition
         :name "test-xf" :input-type :string :output-type :string
         :transform-fn (lambda (x) (string-upcase x)))))

;;; Broken plugin for validation tests
(defclass broken-plugin (orrery/plugin:plugin) ())

(defmethod orrery/plugin:plugin-command-definitions ((p broken-plugin))
  (list (orrery/plugin:make-command-definition
         :name "broken-cmd" :handler nil :description "No handler")))

(define-test plugin-sdk-suite

  ;; ─── Plugin protocol ───

  (define-test plugin-class-exists
    (true (find-class 'orrery/plugin:plugin nil)))

  (define-test plugin-card-method
    (true (fboundp 'orrery/plugin:plugin-card-definitions)))

  (define-test plugin-command-method
    (true (fboundp 'orrery/plugin:plugin-command-definitions)))

  (define-test plugin-transformer-method
    (true (fboundp 'orrery/plugin:plugin-transformer-definitions)))

  ;; ─── Registration ───

  (define-test register-and-find
    (let ((p (make-instance 'test-plugin :name "test" :version "1.0")))
      (orrery/plugin:register-plugin p)
      (true (orrery/plugin:find-plugin "test"))
      (is string= "test" (orrery/plugin:plugin-name (orrery/plugin:find-plugin "test")))
      (orrery/plugin:unregister-plugin "test")
      (is eq nil (orrery/plugin:find-plugin "test"))))

  (define-test list-plugins-non-empty
    (let ((p (make-instance 'test-plugin :name "listed" :version "1.0")))
      (orrery/plugin:register-plugin p)
      (true (> (length (orrery/plugin:list-plugins)) 0))
      (orrery/plugin:unregister-plugin "listed")))

  ;; ─── Aggregation ───

  (define-test all-card-definitions-collects
    (let ((p (make-instance 'test-plugin :name "agg-test" :version "1.0")))
      (orrery/plugin:register-plugin p)
      (let ((cards (orrery/plugin:all-card-definitions)))
        (true (> (length cards) 0))
        (true (find "test-card" cards :key #'orrery/plugin:cd-name :test #'string=)))
      (orrery/plugin:unregister-plugin "agg-test")))

  (define-test all-commands-collects
    (let ((p (make-instance 'test-plugin :name "cmd-test" :version "1.0")))
      (orrery/plugin:register-plugin p)
      (let ((cmds (orrery/plugin:all-command-definitions)))
        (true (find "test-cmd" cmds :key #'orrery/plugin:cmd-name :test #'string=)))
      (orrery/plugin:unregister-plugin "cmd-test")))

  (define-test all-transformers-collects
    (let ((p (make-instance 'test-plugin :name "xf-test" :version "1.0")))
      (orrery/plugin:register-plugin p)
      (let ((xfs (orrery/plugin:all-transformer-definitions)))
        (true (find "test-xf" xfs :key #'orrery/plugin:td-name :test #'string=)))
      (orrery/plugin:unregister-plugin "xf-test")))

  ;; ─── Validation ───

  (define-test validate-valid-plugin
    (let* ((p (make-instance 'test-plugin :name "valid" :version "1.0"))
           (result (orrery/plugin:validate-plugin p)))
      (is eq t (orrery/plugin:pvr-valid-p result))
      (is = 0 (length (orrery/plugin:pvr-errors result)))))

  (define-test validate-broken-plugin-has-errors
    (let* ((p (make-instance 'broken-plugin :name "broken" :version "1.0"))
           (result (orrery/plugin:validate-plugin p)))
      (is eq nil (orrery/plugin:pvr-valid-p result))
      (true (> (length (orrery/plugin:pvr-errors result)) 0))))

  (define-test validate-empty-name-error
    (let* ((p (make-instance 'test-plugin :name "" :version "1.0"))
           (result (orrery/plugin:validate-plugin p)))
      (is eq nil (orrery/plugin:pvr-valid-p result))
      (true (find "name" (orrery/plugin:pvr-errors result)
                  :test (lambda (s e) (search s e))))))

  ;; ─── Struct constructors ───

  (define-test card-definition-struct
    (let ((c (orrery/plugin:make-card-definition :name "c" :title "T" :priority 5)))
      (is string= "c" (orrery/plugin:cd-name c))
      (is string= "T" (orrery/plugin:cd-title c))
      (is = 5 (orrery/plugin:cd-priority c))))

  (define-test transformer-types
    (let ((t1 (orrery/plugin:make-transformer-definition
               :name "t" :input-type :json :output-type :string)))
      (is eq :json (orrery/plugin:td-input-type t1))
      (is eq :string (orrery/plugin:td-output-type t1)))))
