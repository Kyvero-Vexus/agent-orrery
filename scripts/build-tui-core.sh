#!/usr/bin/env bash
# Build precompiled SBCL core for TUI E2E testing
#
# Usage:
#   ./scripts/build-tui-core.sh [--force]
#
# Output:
#   artifacts/tui-core.core
#
# The core reduces startup from ~31s to <5s.
# Rebuild whenever agent-orrery source changes significantly.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/artifacts/tui-core.core"
SCRIPT="$ROOT/scripts/build-tui-core.lisp"
FORCE="${1:-}"

export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

if [[ -f "$CORE" && "$FORCE" != "--force" ]]; then
  echo "[build-tui-core] Core already exists: $CORE"
  echo "[build-tui-core] Use --force to rebuild."
  exit 0
fi

echo "[build-tui-core] Building precompiled SBCL image..."
echo "[build-tui-core]   Script: $SCRIPT"
echo "[build-tui-core]   Output: $CORE"
echo ""

START=$(date +%s)

sbcl --noinform --disable-debugger \
  --load "$SCRIPT"

END=$(date +%s)
ELAPSED=$((END - START))

if [[ -f "$CORE" ]]; then
  SIZE=$(du -sh "$CORE" | cut -f1)
  echo ""
  echo "[build-tui-core] Done in ${ELAPSED}s — core: $CORE ($SIZE)"
else
  echo "[build-tui-core] ERROR: core file not created!"
  exit 1
fi
