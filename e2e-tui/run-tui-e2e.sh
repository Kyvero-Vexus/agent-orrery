#!/usr/bin/env bash
# Deterministic TUI E2E runner for Agent Orrery (mcp-tui-driver)
#
# Usage:
#   ./e2e-tui/run-tui-e2e.sh              # run all T1-T6 scenarios
#   MCP_TUI_DRIVER=/path/to/bin ./e2e-tui/run-tui-e2e.sh
#
# Prerequisites:
#   1. mcp-tui-driver binary installed (cargo install from source)
#   2. SBCL + Quicklisp + agent-orrery ASDF system loadable
#   3. Node.js (for test harness)
#
# Outputs:
#   test-results/tui-artifacts/            screenshots, transcripts, recording
#   test-results/tui-artifacts/tui-e2e-report.json   JSON report
#   test-results/tui-artifacts/tui-e2e-session.cast  asciinema recording

set -euo pipefail
cd "$(dirname "$0")/.."

export MCP_TUI_DRIVER="${MCP_TUI_DRIVER:-mcp-tui-driver}"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

echo "=== Agent Orrery TUI E2E (mcp-tui-driver) ==="
echo "  Driver: $(which "$MCP_TUI_DRIVER" 2>/dev/null || echo 'NOT FOUND')"
echo "  SBCL:   $(which sbcl 2>/dev/null || echo 'NOT FOUND')"
echo "  Node:   $(node --version 2>/dev/null || echo 'NOT FOUND')"
echo ""

# Verify prerequisites
if ! command -v "$MCP_TUI_DRIVER" &>/dev/null; then
  echo "ERROR: mcp-tui-driver not found. Install with:"
  echo "  cargo install --git https://github.com/michaellee8/mcp-tui-driver"
  exit 1
fi

if ! command -v sbcl &>/dev/null; then
  echo "ERROR: sbcl not found."
  exit 1
fi

# Clean old artifacts
rm -rf test-results/tui-artifacts
mkdir -p test-results/tui-artifacts

# Run scenarios
node e2e-tui/tests/tui-scenarios.js
EXIT=$?

echo ""
echo "=== Artifacts ==="
echo "  test-results/tui-artifacts/"
ls -la test-results/tui-artifacts/ 2>/dev/null || true

exit $EXIT
