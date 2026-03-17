;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; design-doc-sync-gate-tests.lisp — Tests for design-doc sync checker
;;; Bead: agent-orrery-mmw

(in-package #:orrery/harness-tests)

(define-test design-doc-sync-gate-tests)

(defun %make-temp-doc-dir (suffix)
  (let ((dir (format nil "/tmp/orrery-docsync-~A-~D/" suffix (get-universal-time))))
    (ensure-directories-exist (merge-pathnames "dummy" dir))
    dir))

(defun %cleanup-temp-doc-dir (dir)
  (when (probe-file dir)
    (dolist (f (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                           (pathname dir))))
      (ignore-errors (delete-file f)))))

(define-test (design-doc-sync-gate-tests requirement-detection)
  (true (orrery/adapter:bead-requires-design-docs-p
         "foo. Mandatory: develop/update Common Lisp design docs in /home/slime/projects/emacsen-design-docs. bar"))
  (false (orrery/adapter:bead-requires-design-docs-p
          "no requirement sentence")))

(define-test (design-doc-sync-gate-tests find-docs-for-bead)
  (let* ((dir (%make-temp-doc-dir "find"))
         (doc1 (merge-pathnames "a.md" dir))
         (doc2 (merge-pathnames "b.md" dir)))
    (unwind-protect
         (progn
           (with-open-file (s doc1 :direction :output :if-exists :supersede)
             (write-string "bead: agent-orrery-mmw" s))
           (with-open-file (s doc2 :direction :output :if-exists :supersede)
             (write-string "bead: something-else" s))
           (let ((matches (orrery/adapter:find-design-docs-for-bead "agent-orrery-mmw" dir)))
             (is = 1 (length matches))
             (true (search "a.md" (first matches)))))
      (%cleanup-temp-doc-dir dir))))

(define-test (design-doc-sync-gate-tests evaluate-sync-pass)
  (let* ((dir (%make-temp-doc-dir "pass"))
         (doc (merge-pathnames "mmw.md" dir))
         (description "Task. Mandatory: develop/update Common Lisp design docs in /home/slime/projects/emacsen-design-docs."))
    (unwind-protect
         (progn
           (with-open-file (s doc :direction :output :if-exists :supersede)
             (write-string "evidence for bead agent-orrery-mmw" s))
           (let ((res (orrery/adapter:evaluate-design-doc-sync "agent-orrery-mmw" description dir)))
             (true (orrery/adapter:ddsr-requirement-present-p res))
             (true (orrery/adapter:ddsr-docs-found-p res))
             (true (search "match_count" (orrery/adapter:design-doc-sync-result->json res)))))
      (%cleanup-temp-doc-dir dir))))

(define-test (design-doc-sync-gate-tests evaluate-sync-fail)
  (let* ((dir (%make-temp-doc-dir "fail"))
         (res (orrery/adapter:evaluate-design-doc-sync "agent-orrery-mmw" "missing requirement" dir)))
    (false (orrery/adapter:ddsr-requirement-present-p res))
    (false (orrery/adapter:ddsr-docs-found-p res))))

(define-test (design-doc-sync-gate-tests acceptance-non-epic-pass)
  (let* ((dir (%make-temp-doc-dir "accept"))
         (doc (merge-pathnames "mmw.md" dir))
         (desc "Mandatory: develop/update Common Lisp design docs in /home/slime/projects/emacsen-design-docs."))
    (unwind-protect
         (progn
           (with-open-file (s doc :direction :output :if-exists :supersede)
             (write-string "agent-orrery-mmw" s))
           (let ((res (orrery/adapter:evaluate-bead-acceptance
                       "agent-orrery-mmw" "Typed CL design-doc sync checker" desc dir "test-results/")))
             (true (orrery/adapter:bar-overall-ok-p res))
             (true (search "\"overall\":true" (orrery/adapter:bead-acceptance-result->json res)))))
      (%cleanup-temp-doc-dir dir))))

(define-test (design-doc-sync-gate-tests acceptance-epic3-fails-without-artifacts)
  (let* ((dir (%make-temp-doc-dir "accept-epic3"))
         (doc (merge-pathnames "igw.md" dir))
         (desc "Epic 3 mcp-tui-driver T1-T6. Mandatory: develop/update Common Lisp design docs in /home/slime/projects/emacsen-design-docs."))
    (unwind-protect
         (progn
           (with-open-file (s doc :direction :output :if-exists :supersede)
             (write-string "agent-orrery-igw" s))
           (let ((res (orrery/adapter:evaluate-bead-acceptance
                       "agent-orrery-igw" "Epic 3 closure" desc dir "/tmp/nonexistent-artifacts-root/")))
             (false (orrery/adapter:bar-overall-ok-p res))
             (false (orrery/adapter:bar-epic3-evidence-ok-p res))))
      (%cleanup-temp-doc-dir dir))))

(define-test (design-doc-sync-gate-tests epic4-guard-fails-without-artifacts)
  (false (orrery/adapter:epic4-s1-s6-evidence-ok-p "/tmp/nonexistent-e2e-report-dir/")))

(define-test (design-doc-sync-gate-tests acceptance-epic4-fails-without-artifacts)
  (let* ((dir (%make-temp-doc-dir "accept-epic4"))
         (doc (merge-pathnames "eb045.md" dir))
         (desc "Epic 4 Playwright S1-S6 for agent-orrery-eb0.4.5. Mandatory: develop/update Common Lisp design docs in /home/slime/projects/emacsen-design-docs."))
    (unwind-protect
         (progn
           (with-open-file (s doc :direction :output :if-exists :supersede)
             (write-string "agent-orrery-eb0.4.5" s))
           (let ((res (orrery/adapter:evaluate-bead-acceptance
                       "agent-orrery-eb0.4.5" "Epic 4 closure" desc dir "/tmp/nonexistent-artifacts-root/")))
             (false (orrery/adapter:bar-overall-ok-p res))
             (false (orrery/adapter:bar-epic4-evidence-ok-p res))))
      (%cleanup-temp-doc-dir dir))))
