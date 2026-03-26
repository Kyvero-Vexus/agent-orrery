#!/usr/bin/env bash
# ci/run-mcclim-gate.sh — McCLIM E2E CI gate for Agent Orrery (Epic 5)
#
# Deterministic run command:
#   bash ci/run-mcclim-gate.sh
#
# What it does:
#   1. Runs all McCLIM CLIM gate scenarios (S1-S6) via SBCL
#   2. Captures JSON artifact as test-results/epic5-clim-gate.json
#   3. Exits with 0 if all scenarios pass, 1 otherwise
#
# Artifacts:
#   test-results/epic5-clim-gate.json    JSON results payload
#
# Exit codes:
#   0  All scenarios passed
#   1  One or more scenarios failed

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Agent Orrery McCLIM CI Gate ==="
echo "  Repo: $REPO_ROOT"
echo ""

# Set library path for SBCL (required for McCLIM)
export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

# Ensure test-results directory exists
mkdir -p test-results

# Run the Epic 5 CLIM gate
echo "[gate] Running McCLIM E2E scenarios (S1-S6)..."
/home/slime/.guix-profile/bin/sbcl --script ci/e2e-epic5-clim-gate.lisp
EXIT_CODE=$?

# Summary
echo ""
echo "=== Gate Summary ==="
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "  PASS: All McCLIM scenarios passed"
  echo "  Artifact: test-results/epic5-clim-gate.json"
else
  echo "  FAIL: One or more scenarios failed (exit $EXIT_CODE)"
  echo "  Artifact: test-results/epic5-clim-gate.json"
fi
echo ""

exit "$EXIT_CODE"
