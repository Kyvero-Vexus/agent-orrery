# Changelog

All notable changes to Agent Orrery are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

---

## [Unreleased] — v2.0 release candidate

### Added

#### Epic 8 — v2 Coalton Module Suite
- `src/coalton/cost-optimizer.lisp` — typed cost optimization with budget policy enforcement
- `src/coalton/capacity-planner.lisp` — session capacity forecasting and threshold alerts
- `src/coalton/session-analytics.lisp` — per-session metrics, drift detection, efficiency scoring
- `src/coalton/audit-trail.lisp` — immutable operator action log with query API
- CL bridge adapters: `cost-optimizer-bridge.lisp`, `capacity-planner-bridge.lisp`, `session-analytics-bridge.lisp`, `audit-trail-bridge.lisp`

#### Epic 9 — E2E Gate (in progress)
- Playwright S1-S8 E2E framework for web interface
- mcp-tui-driver T1-T8 E2E framework for TUI interface
- CI gates: `ci/check-playwright-artifact-canonicalizer.lisp`, `ci/check-tui-continuity-preflight.lisp`, `ci/check-unified-closure-gate.lisp`
- Evidence schema harmonizer for cross-framework closure dashboards

#### Epic 10 — Release Hardening v2
- OpenAPI 3.1 spec at `docs/api/openapi.yaml`
- Architecture documentation refresh with v2 module map (`docs/ARCHITECTURE.md`)
- Plugin SDK v2: `plugin-on-anomaly-detection`, `plugin-on-notification-routed` lifecycle hooks
- CHANGELOG (this file)
- Operator runbook v2 section

#### Epic 11 — Protocol Boundary
- Typed protocol schema with boundary contract enforcement
- Protocol replay bridge with deterministic cross-UI parity fixtures
- Strict declaration CI gate for all protocol-schema packages

### Changed

- `src/plugin/sdk.lisp` — added v2 lifecycle hook generics for all Coalton modules
- `docs/OPERATOR-RUNBOOK.md` — v2 module troubleshooting, resilience suite docs
- `docs/ARCHITECTURE.md` — v2 module interaction diagrams, E2E evidence policy

### Fixed

- `playwright-verifier-hook-adapter.lisp` — removed duplicate `playwright-preflight-verdict` struct definition
- `playwright-replay-table.lisp` — renamed `playwright-preflight-record` to `playwright-preflight-hook` (pph-) to avoid conc-name collision with replay-protocol-bridge

---

## [1.0.0] — Initial Release

### Added
- Core dashboard (TUI + Web + McClim surfaces)
- OpenClaw adapter protocol
- Session monitoring, health checks, cron job management
- Typed domain core with Coalton modules: core, configuration, policy, usage-analytics, notification-routing, scenario-planning, budget-policy, anomaly-detector
- E2E framework scaffolding (Playwright + mcp-tui-driver)
- Plugin system with card/command/transformer definitions
