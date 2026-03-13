# Agent Orrery — Build & CI Targets
#
# Usage:
#   make test          — run test suite
#   make check-types   — run type policy enforcement
#   make ci            — run all CI checks
#   make clean         — remove compiled fasls

SBCL ?= sbcl

.PHONY: test check-types e2e-smoke ci clean

test:
	@$(SBCL) --load ci/run-tests.lisp

check-types:
	@$(SBCL) --load ci/check-types.lisp

e2e-smoke:
	@$(SBCL) --load ci/e2e-smoke.lisp

ci: check-types test e2e-smoke
	@echo ""
	@echo "=== All CI checks passed ==="

clean:
	@find . -name '*.fasl' -delete
	@echo "Cleaned fasls."
