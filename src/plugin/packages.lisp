;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;; packages.lisp — Plugin SDK packages
;;; Bead: agent-orrery-eb0.6.1

(defpackage #:orrery/plugin
  (:use #:cl)
  (:export
   ;; Plugin protocol
   #:plugin #:plugin-name #:plugin-version #:plugin-description
   #:plugin-card-definitions #:plugin-command-definitions
   #:plugin-transformer-definitions
   ;; Card protocol
   #:card-definition #:make-card-definition
   #:cd-name #:cd-title #:cd-renderer #:cd-data-fn #:cd-priority
   ;; Command protocol
   #:command-definition #:make-command-definition
   #:cmd-name #:cmd-handler #:cmd-description #:cmd-keystroke
   ;; Transformer protocol
   #:transformer-definition #:make-transformer-definition
   #:td-name #:td-input-type #:td-output-type #:td-transform-fn
   ;; Registry
   #:*plugin-registry* #:register-plugin #:unregister-plugin
   #:find-plugin #:list-plugins
   #:all-card-definitions #:all-command-definitions
   #:all-transformer-definitions
   ;; Validation
   #:validate-plugin #:plugin-validation-result
   #:make-plugin-validation-result
   #:pvr-valid-p #:pvr-errors #:pvr-warnings))
