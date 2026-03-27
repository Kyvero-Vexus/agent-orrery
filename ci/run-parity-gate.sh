#!/usr/bin/env bash
#
# run-parity-gate.sh — Cross-UI Parity Gate for CI
#
# Runs the cross-UI parity suite and produces a conformance report.
# Exit 0 on pass, non-zero on fail.
#
# Usage:
#   ./ci/run-parity-gate.sh [--json REPORT_PATH]
#
# Environment:
#   WEB_EVIDENCE_DIR   — Web evidence directory (default: test-results/e2e-report/)
#   TUI_EVIDENCE_DIR   — TUI evidence directory (default: test-results/tui-artifacts/)
#   SBCL               — SBCL executable path (default: sbcl)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
JSON_OUTPUT=""
TIMESTAMP="$(date +%s)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

# Configuration
WEB_EVIDENCE_DIR="${WEB_EVIDENCE_DIR:-${PROJECT_ROOT}/test-results/e2e-report/}"
TUI_EVIDENCE_DIR="${TUI_EVIDENCE_DIR:-${PROJECT_ROOT}/test-results/tui-artifacts/}"
SBCL="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-/home/slime/quicklisp/setup.lisp}"

echo "=== Cross-UI Parity Gate ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Web Evidence: ${WEB_EVIDENCE_DIR}"
echo "TUI Evidence: ${TUI_EVIDENCE_DIR}"
echo

# Check evidence directories exist
if [[ ! -d "${WEB_EVIDENCE_DIR}" ]]; then
    echo "WARNING: Web evidence directory not found: ${WEB_EVIDENCE_DIR}"
fi
if [[ ! -d "${TUI_EVIDENCE_DIR}" ]]; then
    echo "WARNING: TUI evidence directory not found: ${TUI_EVIDENCE_DIR}"
fi

# Create the Lisp parity gate checker script
PARITY_CHECK_SCRIPT=$(mktemp --suffix=.lisp)
trap "rm -f ${PARITY_CHECK_SCRIPT}" EXIT

cat > "${PARITY_CHECK_SCRIPT}" << 'PARITY_LISP'
;;; run-parity-gate.lisp — Execute cross-UI parity suite and check results

(load "#{QUICKLISP_SETUP}")
(require :asdf)

;; Set up ASDF path
(pushnew #P"/home/slime/projects/agent-orrery/" asdf:*central-registry* :test #'equal)
(asdf:clear-source-registry)

(handler-case
    (asdf:load-system :agent-orrery)
  (error (e)
    (format *error-output* "~&LOAD ERROR: Failed to load agent-orrery: ~A~%" e)
    (sb-ext:exit :code 2)))

(let* ((pkg (find-package "ORRERY/ADAPTER"))
       (run-sym (and pkg (find-symbol "RUN-CROSS-UI-PARITY-SUITE" pkg)))
       (pass-sym (and pkg (find-symbol "CUC-PASS-P" pkg)))
       (json-sym (and pkg (find-symbol "CROSS-UI-CONFORMANCE-REPORT->JSON" pkg)))
       (mk-collector-sym (and pkg (find-symbol "MAKE-EMPTY-COLLECTOR" pkg)))
       (web-manifest-sym (and pkg (find-symbol "COMPILE-PLAYWRIGHT-EVIDENCE-MANIFEST" pkg)))
       (tui-manifest-sym (and pkg (find-symbol "COMPILE-MCP-TUI-EVIDENCE-MANIFEST" pkg))))
  (unless (and run-sym pass-sym json-sym mk-collector-sym)
    (format *error-output* "~&ERROR: Required parity suite symbols not found~%")
    (sb-ext:exit :code 2))
  
  (let* ((timestamp (parse-integer (or (uiop:getenv "PARITY_TIMESTAMP") "0")))
         (web-dir (or (uiop:getenv "WEB_EVIDENCE_DIR") "test-results/e2e-report/"))
         (tui-dir (or (uiop:getenv "TUI_EVIDENCE_DIR") "test-results/tui-artifacts/"))
         (web-cmd (or (uiop:getenv "WEB_COMMAND") "cd e2e && ./run-e2e.sh"))
         (tui-cmd (or (uiop:getenv "TUI_COMMAND") "make e2e-tui"))
         (collector (funcall mk-collector-sym))
         (web-manifest (when (and web-manifest-sym (probe-file web-dir))
                         (funcall web-manifest-sym web-dir web-cmd)))
         (tui-manifest (when (and tui-manifest-sym (probe-file tui-dir))
                         (funcall tui-manifest-sym tui-dir tui-cmd)))
         (report (funcall run-sym collector
                          :timestamp timestamp
                          :web-manifest web-manifest
                          :tui-manifest tui-manifest))
         (pass-p (funcall pass-sym report))
         (json (funcall json-sym report)))
    
    ;; Output JSON report
    (format t "~A~%" json)
    (terpri)
    
    ;; Summary
    (format t "~&=== Parity Gate Summary ===~%")
    (format t "Overall: ~A~%" (if pass-p "PASS" "FAIL"))
    
    ;; Exit with appropriate code
    (sb-ext:exit :code (if pass-p 0 1))))
PARITY_LISP

# Substitute the quicklisp path
sed -i "s|#{QUICKLISP_SETUP}|${QUICKLISP_SETUP}|g" "${PARITY_CHECK_SCRIPT}"

# Set environment for the Lisp script
export PARITY_TIMESTAMP="${TIMESTAMP}"
export WEB_EVIDENCE_DIR="${WEB_EVIDENCE_DIR}"
export TUI_EVIDENCE_DIR="${TUI_EVIDENCE_DIR}"

# Run the parity check
echo "Running cross-UI parity suite..."
cd "${PROJECT_ROOT}"

if ! LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}" \
     "${SBCL}" --script "${PARITY_CHECK_SCRIPT}" 2>&1 | tee /tmp/parity-output.txt; then
    EXIT_CODE=${PIPESTATUS[0]}
    echo
    echo "=== PARITY GATE FAILED ==="
    cat /tmp/parity-output.txt
    exit ${EXIT_CODE:-1}
fi

# Extract JSON if requested
if [[ -n "${JSON_OUTPUT}" ]]; then
    # Extract JSON from output (first line that starts with {)
    grep -m1 '^{' /tmp/parity-output.txt > "${JSON_OUTPUT}" 2>/dev/null || true
    echo "JSON report saved to: ${JSON_OUTPUT}"
fi

echo
echo "=== PARITY GATE PASSED ==="
exit 0
