#!/usr/bin/env bash
# Deterministic E2E runner for Agent Orrery Web Dashboard (Epic 4)
#
# Usage:
#   ./run-e2e.sh                  # run all S1-S6 with traces+screenshots
#   ./run-e2e.sh dashboard       # run single spec file
#   BASE_URL=http://host:port ./run-e2e.sh
#
# Prerequisites:
#   1. CL web server running: sbcl --load e2e/start-server.lisp
#   2. npm install in e2e/
#
# Outputs:
#   ../test-results/e2e-report/      HTML report
#   ../test-results/e2e-artifacts/   traces, screenshots, videos

set -euo pipefail
cd "$(dirname "$0")"

export BASE_URL="${BASE_URL:-http://localhost:7890}"

echo "=== Agent Orrery E2E (Playwright) ==="
echo "  BASE_URL: $BASE_URL"
echo "  Spec:     ${1:-all}"
echo ""

if [ -n "${1:-}" ]; then
  npx playwright test "tests/${1}.spec.ts" --trace on
else
  npx playwright test --trace on
fi

EXIT=$?
echo ""
echo "=== Report ==="
echo "  npx playwright show-report ../test-results/e2e-report"
exit $EXIT
