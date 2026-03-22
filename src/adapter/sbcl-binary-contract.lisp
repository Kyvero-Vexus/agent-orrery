;;; sbcl-binary-contract.lisp — deterministic SBCL selection contract for CLI invocations

(in-package #:orrery/adapter)

(declaim (ftype (function () (values string &optional)) selected-sbcl-binary))
(defun selected-sbcl-binary ()
  "Return deterministic SBCL executable path/name.

Semantics:
- If SBCL_BIN is present and non-empty after trimming, return it.
- Otherwise return the stable default executable name sbcl."
  (let* ((raw (or (uiop:getenv "SBCL_BIN") ""))
         (trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) raw)))
    (if (plusp (length trimmed))
        trimmed
        "sbcl")))

(declaim (ftype (function () (values string &optional)) selected-sbcl-binary-json-field))
(defun selected-sbcl-binary-json-field ()
  "Return a JSON key/value fragment exposing the selected SBCL binary."
  (format nil "\"selected_sbcl_binary\":\"~A\""
          (selected-sbcl-binary)))
