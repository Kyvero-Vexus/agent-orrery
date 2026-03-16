;;; e2e-epic5-clim-gate.lisp — Deterministic Epic 5 CLIM gate runner

(load "/home/slime/quicklisp/setup.lisp")
(ql:quickload :agent-orrery :silent t)

(let* ((results (orrery/mcclim:run-epic5-scenarios))
       (json (orrery/mcclim:epic5-results->json results))
       (artifact-path #p"test-results/epic5-clim-gate.json")
       (failed (count-if-not #'orrery/mcclim:s5r-pass-p results)))
  (uiop:ensure-all-directories-exist (list artifact-path))
  (with-open-file (s artifact-path :direction :output :if-exists :supersede :if-does-not-exist :create)
    (write-string json s))
  (format t "~A~%" json)
  (format t "~&Artifact: ~A~%" artifact-path)
  (if (> failed 0)
      (uiop:quit 1)
      (uiop:quit 0)))
