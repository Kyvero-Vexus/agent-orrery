;;; types.lisp

(in-package #:orrery/protocol-schema)

(deftype protocol-surface () '(member :tui :web :mcclim))
(deftype protocol-kind () '(member :status :session :cron :health :alert :audit :analytics :capacity :cost :command :event))

(defstruct (schema-field (:conc-name sf-))
  (name :id :type keyword)
  (required-p t :type boolean)
  (type-tag :string :type keyword)
  (default-value nil :type t))

(defstruct (schema-spec (:conc-name ss-))
  (surface :tui :type protocol-surface)
  (kind :status :type protocol-kind)
  (version "1.0" :type string)
  (fields nil :type list))
