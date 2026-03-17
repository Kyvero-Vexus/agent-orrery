#!/usr/bin/env bash
# Agent Orrery — Launch TUI for manual testing
# Bead: agent-orrery-c7l

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
QL_SETUP="${QL_SETUP:-$HOME/quicklisp/setup.lisp}"

if [[ ! -f "$QL_SETUP" ]]; then
  echo "ERROR: Quicklisp setup not found at $QL_SETUP"
  echo "Set QL_SETUP=/path/to/setup.lisp"
  exit 1
fi

echo "=== Agent Orrery TUI ==="
echo "  Root: $ROOT"
echo "  Quicklisp: $QL_SETUP"
echo "  LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

sbcl --noinform --disable-debugger \
  --eval "(load \"$QL_SETUP\")" \
  --eval "(push #p\"$ROOT/\" asdf:*central-registry*)" \
  --eval '(asdf:load-system "agent-orrery/test-harness")' \
  --eval '(let* ((adapter (orrery/harness:make-fixture-adapter))
                 (store (orrery/store:snapshot-from-adapter adapter)))
            (orrery/tui:start-dashboard :store store))' \
  --quit
