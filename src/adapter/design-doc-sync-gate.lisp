;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; design-doc-sync-gate.lisp — Typed design-doc sync checker for bead acceptance
;;; Bead: agent-orrery-mmw

(in-package #:orrery/adapter)

(defparameter *design-doc-requirement-sentence*
  "Mandatory: develop/update Common Lisp design docs in /home/slime/projects/emacsen-design-docs"
  "Exact requirement sentence expected in bead descriptions.")

(defstruct (design-doc-sync-result (:conc-name ddsr-))
  (bead-id "" :type string)
  (requirement-present-p nil :type boolean)
  (docs-found-p nil :type boolean)
  (matching-doc-paths nil :type list)
  (detail "" :type string))

(defstruct (bead-acceptance-result (:conc-name bar-))
  (bead-id "" :type string)
  (design-doc-sync-ok-p nil :type boolean)
  (epic3-evidence-ok-p t :type boolean)
  (epic4-evidence-ok-p t :type boolean)
  (overall-ok-p nil :type boolean)
  (detail "" :type string))

(declaim
 (ftype (function (string) (values boolean &optional)) bead-requires-design-docs-p)
 (ftype (function (string string) (values list &optional)) find-design-docs-for-bead)
 (ftype (function (string string string) (values design-doc-sync-result &optional))
        evaluate-design-doc-sync)
 (ftype (function (string string string string string) (values bead-acceptance-result &optional))
        evaluate-bead-acceptance)
 (ftype (function (design-doc-sync-result) (values string &optional))
        design-doc-sync-result->json)
 (ftype (function (bead-acceptance-result) (values string &optional))
        bead-acceptance-result->json))

(defun bead-requires-design-docs-p (description)
  "True if DESCRIPTION includes the mandatory design-doc requirement sentence." 
  (declare (type string description))
  (not (null (search *design-doc-requirement-sentence* description :test #'char-equal))))

(defun find-design-docs-for-bead (bead-id docs-root)
  "Return markdown files under DOCS-ROOT containing BEAD-ID." 
  (declare (type string bead-id docs-root))
  (let ((matches nil)
        (pattern (string-downcase bead-id)))
    (when (probe-file docs-root)
      (dolist (path (directory (merge-pathnames (make-pathname :name :wild :type "md" :directory '(:relative :wild-inferiors))
                                                (pathname docs-root))))
        (let* ((name (namestring path))
               (content (ignore-errors
                          (with-open-file (s path :direction :input)
                            (let ((buf (make-string (file-length s))))
                              (read-sequence buf s)
                              buf)))))
          (when (and content (search pattern (string-downcase content)))
            (push name matches)))))
    (sort (nreverse matches) #'string<)))

(defun evaluate-design-doc-sync (bead-id description docs-root)
  "Evaluate whether BEAD-ID has mandatory requirement text and matching docs." 
  (declare (type string bead-id description docs-root))
  (let* ((requirement-present (bead-requires-design-docs-p description))
         (matches (find-design-docs-for-bead bead-id docs-root))
         (docs-found (not (null matches))))
    (make-design-doc-sync-result
     :bead-id bead-id
     :requirement-present-p requirement-present
     :docs-found-p docs-found
     :matching-doc-paths matches
     :detail (format nil "bead=~A requirement=~A docs=~A count=~D"
                     bead-id requirement-present docs-found (length matches)))))

(defun %bead-targets-epic3-p (title description)
  (let ((txt (string-downcase (format nil "~A ~A" title description))))
    (or (search "epic 3" txt)
        (search "mcp-tui-driver" txt)
        (search "t1-t6" txt))))

(defun %bead-targets-epic4-p (title description)
  (let ((txt (string-downcase (format nil "~A ~A" title description))))
    (or (search "epic 4" txt)
        (search "playwright" txt)
        (search "s1-s6" txt))))

(defun evaluate-bead-acceptance (bead-id title description docs-root artifacts-root)
  "Evaluate closure eligibility for a bead.
Checks: design-doc sync + Epic3/Epic4 evidence policy gates when applicable." 
  (declare (type string bead-id title description docs-root artifacts-root))
  (let* ((sync (evaluate-design-doc-sync bead-id description docs-root))
         (sync-ok (and (ddsr-requirement-present-p sync)
                       (ddsr-docs-found-p sync)))
         (epic3-needed (%bead-targets-epic3-p title description))
         (epic4-needed (%bead-targets-epic4-p title description))
         (epic3-ok (if epic3-needed
                       (epic3-t1-t6-evidence-ok-p
                        (namestring (merge-pathnames "tui-artifacts/" artifacts-root)))
                       t))
         (epic4-ok (if epic4-needed
                       (e2e-manifest-valid-p
                        (validate-and-normalize-e2e-manifest :web-playwright
                                                             (namestring (merge-pathnames "e2e-report/" artifacts-root))))
                       t))
         (overall (and sync-ok epic3-ok epic4-ok)))
    (make-bead-acceptance-result
     :bead-id bead-id
     :design-doc-sync-ok-p sync-ok
     :epic3-evidence-ok-p epic3-ok
     :epic4-evidence-ok-p epic4-ok
     :overall-ok-p overall
     :detail (format nil "bead=~A sync=~A epic3=~A epic4=~A"
                     bead-id sync-ok epic3-ok epic4-ok))))

(defun design-doc-sync-result->json (result)
  (declare (type design-doc-sync-result result))
  (format nil
          "{\"bead\":\"~A\",\"requirement_present\":~A,\"docs_found\":~A,\"match_count\":~D,\"detail\":\"~A\"}"
          (ddsr-bead-id result)
          (if (ddsr-requirement-present-p result) "true" "false")
          (if (ddsr-docs-found-p result) "true" "false")
          (length (ddsr-matching-doc-paths result))
          (ddsr-detail result)))

(defun bead-acceptance-result->json (result)
  (declare (type bead-acceptance-result result))
  (format nil
          "{\"bead\":\"~A\",\"design_doc_sync\":~A,\"epic3_evidence\":~A,\"epic4_evidence\":~A,\"overall\":~A,\"detail\":\"~A\"}"
          (bar-bead-id result)
          (if (bar-design-doc-sync-ok-p result) "true" "false")
          (if (bar-epic3-evidence-ok-p result) "true" "false")
          (if (bar-epic4-evidence-ok-p result) "true" "false")
          (if (bar-overall-ok-p result) "true" "false")
          (bar-detail result)))
