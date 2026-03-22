#!/usr/bin/env bash
# scripts/e2e/run-tui-e2e-deterministic.sh
#
# Deterministic runner wrapper for mcp-tui-driver T1-T6 evidence collection.
# Bead: agent-orrery-1ts
#
# Enforces:
#   - Fixed SCENARIO_FILTER=T1,T2,T3,T4,T5,T6
#   - Transcript capture to canonical path
#   - Asciicast recording via asciinema if available
#   - Artifact path normalization
#   - Exit code = 0 iff all T1-T6 scenarios produce required artifacts
#
# Usage:
#   bash scripts/e2e/run-tui-e2e-deterministic.sh
#   TUI_SEED=42 bash scripts/e2e/run-tui-e2e-deterministic.sh
#   TUI_ARTIFACTS_DIR=my-out bash scripts/e2e/run-tui-e2e-deterministic.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

# --- deterministic env -------------------------------------------------------
export SCENARIO_FILTER="${SCENARIO_FILTER:-T1,T2,T3,T4,T5,T6}"
export TUI_SEED="${TUI_SEED:-0}"
export MCP_TUI_DRIVER="${MCP_TUI_DRIVER:-mcp-tui-driver}"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

ARTIFACTS_DIR="${TUI_ARTIFACTS_DIR:-test-results/tui-artifacts}"
TRANSCRIPT_PATH="${TUI_TRANSCRIPT_PATH:-${ARTIFACTS_DIR}/t1-t6-transcript.txt}"
CAST_PATH="${TUI_CAST_PATH:-${ARTIFACTS_DIR}/tui-e2e-session.cast}"
REPORT_PATH="${TUI_REPORT_PATH:-${ARTIFACTS_DIR}/tui-e2e-report.json}"

# --- announce ----------------------------------------------------------------
echo "=== mcp-tui-driver deterministic T1-T6 runner ==="
echo "  SCENARIO_FILTER : $SCENARIO_FILTER"
echo "  TUI_SEED        : $TUI_SEED"
echo "  ARTIFACTS_DIR   : $ARTIFACTS_DIR"
echo "  TRANSCRIPT_PATH : $TRANSCRIPT_PATH"
echo "  CAST_PATH       : $CAST_PATH"
echo "  REPORT_PATH     : $REPORT_PATH"
echo ""

# --- prerequisites -----------------------------------------------------------
if ! command -v "$MCP_TUI_DRIVER" &>/dev/null; then
  echo "ERROR: mcp-tui-driver not found. Install with:"
  echo "  cargo install --git https://github.com/michaellee8/mcp-tui-driver"
  exit 1
fi
if ! command -v sbcl &>/dev/null; then
  echo "ERROR: sbcl not found."
  exit 1
fi
if ! command -v node &>/dev/null; then
  echo "ERROR: node not found."
  exit 1
fi

# --- run scenarios -----------------------------------------------------------
export TUI_ARTIFACTS_DIR="$ARTIFACTS_DIR"
export TUI_TRANSCRIPT_PATH="$TRANSCRIPT_PATH"
export TUI_CAST_PATH="$CAST_PATH"
export TUI_REPORT_PATH="$REPORT_PATH"

bash e2e-tui/run-tui-e2e-t1-t6.sh 2>&1 | tee "$TRANSCRIPT_PATH" || true

EXIT_SCENARIOS=${PIPESTATUS[0]:-0}

# --- validate evidence -------------------------------------------------------
echo ""
echo "=== Validating T1-T6 evidence artifacts ==="
VALIDATE_EXIT=0
if command -v sbcl &>/dev/null; then
  sbcl --script ci/validate-t1-t6-evidence.lisp \
    --tui-evidence-dir "$ARTIFACTS_DIR" \
    --tui-command "cd e2e-tui && ./run-tui-e2e-t1-t6.sh" \
    2>&1 || VALIDATE_EXIT=$?
fi

if [ "$EXIT_SCENARIOS" -ne 0 ] || [ "$VALIDATE_EXIT" -ne 0 ]; then
  echo ""
  echo "FAIL: T1-T6 deterministic run failed (scenarios=$EXIT_SCENARIOS validate=$VALIDATE_EXIT)"
  exit 1
fi

echo ""
echo "PASS: T1-T6 deterministic evidence collected and validated."
exit 0
