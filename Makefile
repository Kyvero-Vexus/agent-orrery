# Agent Orrery — Build & CI Targets
#
# Usage:
#   make test          — run test suite
#   make check-types   — run type policy enforcement
#   make ci            — run all CI checks
#   make clean         — remove compiled fasls

SBCL ?= sbcl

.PHONY: test check-types e2e-smoke e2e-tui e2e-tui-t1-t6 tui-fixture-regression web-fixture-regression unified-preflight run-scripts-gate ci clean

test:
	@$(SBCL) --load ci/run-tests.lisp

check-types:
	@$(SBCL) --load ci/check-types.lisp

e2e-smoke:
	@$(SBCL) --load ci/e2e-smoke.lisp

e2e-tui:
	@echo "=== TUI E2E (mcp-tui-driver, scenarios T1-T8) ==="
	@bash e2e-tui/run-tui-e2e.sh

e2e-tui-t1-t6:
	@echo "=== TUI E2E (mcp-tui-driver, scenarios T1-T6 deterministic) ==="
	@bash e2e-tui/run-tui-e2e-t1-t6.sh

tui-fixture-regression:
	@$(SBCL) --script ci/run-mcp-tui-fixture-regression-matrix.lisp

web-fixture-regression:
	@$(SBCL) --script ci/run-playwright-fixture-regression-matrix.lisp

unified-preflight:
	@$(SBCL) --load ci/check-unified-preflight-bundle.lisp

run-scripts-gate:
	@bash scripts/test-run-scripts.sh

ci: check-types test e2e-smoke web-fixture-regression tui-fixture-regression unified-preflight
	@echo ""
	@echo "=== All CI checks passed ==="

clean:
	@find . -name '*.fasl' -delete
	@echo "Cleaned fasls."
