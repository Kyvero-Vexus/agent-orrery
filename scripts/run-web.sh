#!/usr/bin/env bash
# Agent Orrery — Launch Web UI for manual testing
# Bead: agent-orrery-c7l

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export ORRERY_HOST="${ORRERY_HOST:-127.0.0.1}"
export ORRERY_PORT="${ORRERY_PORT:-7890}"
QL_SETUP="${QL_SETUP:-$HOME/quicklisp/setup.lisp}"

if [[ ! -f "$QL_SETUP" ]]; then
  echo "ERROR: Quicklisp setup not found at $QL_SETUP"
  echo "Set QL_SETUP=/path/to/setup.lisp"
  exit 1
fi

echo "=== Agent Orrery Web UI ==="
echo "  Root: $ROOT"
echo "  URL:  http://${ORRERY_HOST}:${ORRERY_PORT}"
echo "  Quicklisp: $QL_SETUP"
echo "  LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

sbcl --noinform \
  --eval "(load \"$QL_SETUP\")" \
  --eval '(push #p"'"$ROOT"'"/ asdf:*central-registry*)' \
  --eval '(asdf:load-system "agent-orrery")' \
  --eval '(let* ((adapter (orrery/harness:make-fixture-adapter))
                 (store (orrery/store:snapshot-from-adapter adapter)))
            (setf orrery/web:*host* (uiop:getenv "ORRERY_HOST"))
            (setf orrery/web:*port* (parse-integer (uiop:getenv "ORRERY_PORT")))
            (orrery/web:start-server :store store))'
