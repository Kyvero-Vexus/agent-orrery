#!/usr/bin/env bash
# Verify all Agent Orrery run scripts still work end-to-end.
#
# Covers:
#   1) scripts/run-web.sh      (launch + HTTP smoke)
#   2) e2e/run-e2e.sh          (Playwright web E2E)
#   3) scripts/run-tui.sh      (TTY launch + scripted quit)
#   4) e2e-tui/run-tui-e2e.sh  (mcp-tui-driver TUI E2E)
#
# Usage:
#   bash scripts/test-run-scripts.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/test-results/run-script-gate"
mkdir -p "$LOG_DIR"

WEB_URL="${ORRERY_WEB_URL:-http://127.0.0.1:7890}"
WEB_HOST="${ORRERY_HOST:-127.0.0.1}"
WEB_PORT="${ORRERY_PORT:-7890}"
WEB_START_TIMEOUT_S="${ORRERY_WEB_START_TIMEOUT_S:-120}"
TUI_QUIT_DELAY_S="${ORRERY_TUI_QUIT_DELAY_S:-8}"
TUI_TIMEOUT_S="${ORRERY_TUI_TIMEOUT_S:-180}"

WEB_PID=""

cleanup() {
  if [[ -n "${WEB_PID:-}" ]] && kill -0 "$WEB_PID" 2>/dev/null; then
    kill "$WEB_PID" 2>/dev/null || true
    wait "$WEB_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wait_for_web() {
  local start_ts now elapsed
  start_ts="$(date +%s)"
  while true; do
    if curl -fsS "$WEB_URL/" >/dev/null 2>&1; then
      return 0
    fi

    if [[ -n "${WEB_PID:-}" ]] && ! kill -0 "$WEB_PID" 2>/dev/null; then
      echo "ERROR: run-web.sh exited before server became ready" >&2
      return 1
    fi

    now="$(date +%s)"
    elapsed=$((now - start_ts))
    if (( elapsed >= WEB_START_TIMEOUT_S )); then
      echo "ERROR: timed out waiting for web server at $WEB_URL" >&2
      return 1
    fi

    sleep 1
  done
}

echo "=== Run-script gate: Agent Orrery ==="
echo "  Root: $ROOT"
echo "  Logs: $LOG_DIR"
echo ""

echo "[1/4] run-web.sh smoke (launch + HTTP check)"
ORRERY_HOST="$WEB_HOST" ORRERY_PORT="$WEB_PORT" bash scripts/run-web.sh \
  >"$LOG_DIR/run-web.log" 2>&1 &
WEB_PID="$!"

wait_for_web

curl -fsS "$WEB_URL/" >"$LOG_DIR/run-web-home.html"
if ! grep -q "Agent Orrery" "$LOG_DIR/run-web-home.html"; then
  echo "ERROR: web homepage missing expected marker text" >&2
  exit 1
fi

echo "  OK: web server reachable at $WEB_URL"

echo "[2/4] e2e/run-e2e.sh (Playwright web E2E)"
bash e2e/run-e2e.sh | tee "$LOG_DIR/run-e2e.log"
echo "  OK: web E2E passed"

# Stop web server before TUI checks.
cleanup
WEB_PID=""

echo "[3/4] run-tui.sh smoke (TTY launch + scripted quit)"
set -o pipefail
(
  sleep "$TUI_QUIT_DELAY_S"
  printf 'q'
) | TERM=xterm-256color timeout "$TUI_TIMEOUT_S" \
  script -qfec "bash scripts/run-tui.sh" "$LOG_DIR/run-tui.typescript" \
  >"$LOG_DIR/run-tui.stdout" 2>"$LOG_DIR/run-tui.stderr"
set +o pipefail

if ! grep -q "Sessions (1)" "$LOG_DIR/run-tui.typescript"; then
  echo "ERROR: TUI transcript did not show dashboard content" >&2
  exit 1
fi
if ! grep -q "Quitting" "$LOG_DIR/run-tui.typescript"; then
  echo "ERROR: TUI transcript did not show clean quit" >&2
  exit 1
fi

echo "  OK: TUI launched and exited cleanly"

echo "[4/4] e2e-tui/run-tui-e2e.sh (mcp-tui-driver)"
bash e2e-tui/run-tui-e2e.sh | tee "$LOG_DIR/run-tui-e2e.log"
echo "  OK: TUI E2E passed"

echo ""
echo "=== Run-script gate passed ==="
