#!/usr/bin/env bash
# Deterministic T1-T6 runner entrypoint for mcp-tui-driver
# Bead: agent-orrery-igw.3

set -euo pipefail
cd "$(dirname "$0")/.."

export SCENARIO_FILTER="T1,T2,T3,T4,T5,T6"
exec bash e2e-tui/run-tui-e2e.sh
