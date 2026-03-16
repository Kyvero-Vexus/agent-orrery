#!/bin/bash
set -e
cd "$(dirname "$0")"

export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

echo "=== Running Agent Orrery TUI E2E (mcp-tui-driver protocol) ==="
node tests/tui-scenarios.mjs
