#!/usr/bin/env bash
# ci/run-playwright-gate.sh — Playwright E2E CI gate for Agent Orrery (Epic 4)
#
# Deterministic run command:
#   bash ci/run-playwright-gate.sh
#
# What it does:
#   1. Starts the CL fixture web server on port 7890
#   2. Waits up to 30s for the server to be ready
#   3. Runs all Playwright scenarios (S1-S9) via npx playwright test
#   4. Captures traces + screenshots as artifacts
#   5. Kills the server, exits with Playwright's exit code
#
# Artifacts:
#   test-results/e2e-report/         HTML report
#   test-results/e2e-artifacts/      traces, screenshots, videos
#
# Exit codes:
#   0  All scenarios passed
#   1  One or more scenarios failed (or server failed to start)

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PORT="${PORT:-7890}"
BASE_URL="http://localhost:${PORT}"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[gate] Stopping CL server (PID $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "=== Agent Orrery Playwright CI Gate ==="
echo "  Repo:     $REPO_ROOT"
echo "  Base URL: $BASE_URL"
echo ""

# 1. Start the CL web server in background
echo "[gate] Starting CL web server..."
sbcl --noinform --load e2e/start-server.lisp > /tmp/orrery-server.log 2>&1 &
SERVER_PID=$!
echo "[gate] Server PID: $SERVER_PID"

# 2. Wait for server to be ready
echo "[gate] Waiting for server to be ready (up to 30s)..."
READY=0
for i in $(seq 1 30); do
  if curl -sf "${BASE_URL}/" -o /dev/null 2>/dev/null; then
    READY=1
    echo "[gate] Server ready after ${i}s"
    break
  fi
  sleep 1
done

if [ "$READY" -eq 0 ]; then
  echo "[gate] ERROR: Server did not start within 30s"
  echo "[gate] Server log:"
  cat /tmp/orrery-server.log || true
  exit 1
fi

# 3. Run Playwright scenarios
echo "[gate] Running Playwright E2E scenarios..."
cd e2e
BASE_URL="$BASE_URL" npx playwright test --trace on
PW_EXIT=$?

cd "$REPO_ROOT"

# 4. Summary
echo ""
echo "=== Gate Summary ==="
if [ "$PW_EXIT" -eq 0 ]; then
  echo "  PASS: All Playwright scenarios passed"
else
  echo "  FAIL: One or more scenarios failed (exit $PW_EXIT)"
fi
echo "  Report:  test-results/e2e-report/index.html"
echo "  Traces:  test-results/e2e-artifacts/"
echo ""

exit "$PW_EXIT"
