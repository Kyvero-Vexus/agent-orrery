# Agent Orrery — Build & CI Targets
#
# Usage:
#   make test          — run test suite
#   make check-types   — run type policy enforcement
#   make ci            — run all CI checks
#   make clean         — remove compiled fasls

SBCL ?= sbcl

.PHONY: bootstrap-quicklisp test check-types e2e-smoke e2e-tui e2e-tui-t1-t6 e2e-web playwright-ingestion-adapter t1-t6-continuity-preflight mcp-tui-ingestion-adapter mcp-tui-unified-envelope web-s1-s6-bundle-verifier tui-fixture-regression web-fixture-regression unified-preflight unified-closure-gate run-scripts-gate ci clean

bootstrap-quicklisp:
	@$(SBCL) --script ci/bootstrap-quicklisp.lisp

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

e2e-web:
	@echo "=== Web E2E (Playwright, scenarios S1-S8) ==="
	@cd e2e && npx playwright test

playwright-ingestion-adapter:
	@$(SBCL) --script ci/check-playwright-ingestion-adapter.lisp

t1-t6-continuity-preflight:
	@$(SBCL) --script ci/check-t1-t6-continuity-preflight.lisp

mcp-tui-ingestion-adapter:
	@$(SBCL) --script ci/check-mcp-tui-ingestion-adapter.lisp

mcp-tui-unified-envelope:
	@$(SBCL) --script ci/check-mcp-tui-unified-envelope.lisp

web-s1-s6-bundle-verifier:
	@$(SBCL) --script ci/check-playwright-s1-s6-bundle-verifier.lisp

tui-fixture-regression:
	@$(SBCL) --script ci/run-mcp-tui-fixture-regression-matrix.lisp

web-fixture-regression:
	@$(SBCL) --script ci/run-playwright-fixture-regression-matrix.lisp

unified-preflight:
	@$(SBCL) --load ci/check-unified-preflight-bundle.lisp

unified-closure-gate:
	@$(SBCL) --script ci/check-unified-closure-gate.lisp

run-scripts-gate:
	@bash scripts/test-run-scripts.sh

ci: check-types test e2e-smoke web-s1-s6-bundle-verifier playwright-ingestion-adapter t1-t6-continuity-preflight mcp-tui-ingestion-adapter mcp-tui-unified-envelope web-fixture-regression tui-fixture-regression unified-preflight unified-closure-gate
	@echo ""
	@echo "=== All CI checks passed ==="

clean:
	@find . -name '*.fasl' -delete
	@echo "Cleaned fasls."
