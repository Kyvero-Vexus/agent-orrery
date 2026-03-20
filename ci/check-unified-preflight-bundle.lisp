;;; check-unified-preflight-bundle.lisp — unified deterministic preflight bundle emitter/gate

(load #P"/home/slime/quicklisp/setup.lisp")
(require "asdf")

(defun getenv-or (name fallback)
  (or (uiop:getenv name) fallback))

(defun ensure-parent-dir (path)
  (ensure-directories-exist (merge-pathnames "dummy" (pathname path))))

(handler-case
    (progn
      (asdf:load-system :agent-orrery)
      (let* ((web-dir (getenv-or "WEB_EVIDENCE_DIR" "test-results/e2e-report/"))
             (web-cmd (getenv-or "WEB_EVIDENCE_COMMAND" "cd e2e && ./run-e2e.sh"))
             (tui-dir (getenv-or "TUI_EVIDENCE_DIR" "test-results/tui-artifacts/"))
             (tui-cmd (getenv-or "TUI_EVIDENCE_COMMAND" "cd e2e-tui && ./run-tui-e2e-t1-t6.sh"))
             (out-path (getenv-or "UNIFIED_PREFLIGHT_BUNDLE_OUT"
                                  "test-results/preflight/unified-preflight-bundle.json"))
             (pkg (find-package "ORRERY/ADAPTER"))
             (eval-sym (and pkg (find-symbol "EVALUATE-UNIFIED-PREFLIGHT-BUNDLE" pkg)))
             (json-sym (and pkg (find-symbol "UNIFIED-PREFLIGHT-BUNDLE->JSON" pkg)))
             (ok-sym (and pkg (find-symbol "UPB-OVERALL-PASS-P" pkg)))
             (bundle (and eval-sym (funcall eval-sym web-dir web-cmd tui-dir tui-cmd)))
             (json (if (and bundle json-sym)
                       (funcall json-sym bundle)
                       "{\"error\":\"unified-preflight-symbols-missing\"}")))
        (ensure-parent-dir out-path)
        (with-open-file (s out-path :direction :output :if-exists :supersede :if-does-not-exist :create)
          (write-string json s)
          (terpri s))
        (format t "~A~%" json)
        (format t "wrote_bundle=~A~%" out-path)
        (unless (and bundle ok-sym (funcall ok-sym bundle))
          (error "Unified preflight bundle failed"))))
  (error (e)
    (format *error-output* "~&UNIFIED PREFLIGHT BUNDLE ERROR: ~A~%" e)
    (uiop:quit 1)))

(uiop:quit 0)
