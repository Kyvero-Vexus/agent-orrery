#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export TUI_DETERMINISTIC_COMMAND="cd e2e-tui && ./run-tui-e2e-t1-t6.sh"
COMPLETE_DIR="test-results/tui-artifacts-fixture-complete/"
GAPPED_DIR="test-results/tui-artifacts-fixture-gapped/"

rm -rf "$COMPLETE_DIR" "$GAPPED_DIR"

echo "[1/4] generate complete fixture set"
TUI_FIXTURE_DIR="$COMPLETE_DIR" TUI_FIXTURE_MODE="complete" \
  sbcl --load /home/slime/quicklisp/setup.lisp --script ci/generate-mcp-tui-fixtures.lisp

echo "[2/4] closure adapter must pass on complete set"
TUI_EVIDENCE_DIR="$COMPLETE_DIR" TUI_EVIDENCE_COMMAND="$TUI_DETERMINISTIC_COMMAND" \
  sbcl --load /home/slime/quicklisp/setup.lisp --script ci/check-mcp-tui-closure-adapter.lisp > /tmp/orrery-closure-complete.json
if ! grep -q '"pass":true' /tmp/orrery-closure-complete.json; then
  echo "complete fixture set did not pass closure adapter"
  cat /tmp/orrery-closure-complete.json
  exit 1
fi

echo "[3/4] generate gapped fixture set"
TUI_FIXTURE_DIR="$GAPPED_DIR" TUI_FIXTURE_MODE="gapped" \
  sbcl --load /home/slime/quicklisp/setup.lisp --script ci/generate-mcp-tui-fixtures.lisp

echo "[4/4] closure adapter must fail-closed on gapped set"
set +e
TUI_EVIDENCE_DIR="$GAPPED_DIR" TUI_EVIDENCE_COMMAND="$TUI_DETERMINISTIC_COMMAND" \
  sbcl --load /home/slime/quicklisp/setup.lisp --script ci/check-mcp-tui-closure-adapter.lisp > /tmp/orrery-closure-gapped.json
status=$?
set -e
if [ "$status" -eq 0 ] || ! grep -q '"pass":false' /tmp/orrery-closure-gapped.json; then
  echo "gapped fixture set did not fail-closed"
  cat /tmp/orrery-closure-gapped.json
  exit 1
fi

echo "deterministic fixture replay validated"
