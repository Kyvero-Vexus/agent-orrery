# Agent Orrery — Full Delivery Plan

## Mission

Build a statically typed, functional, modular Common Lisp dashboard platform for OpenClaw and similar agentic systems, with parity across three interfaces:

1. Terminal UI
2. Web UI
3. McCLIM UI

## Product Scope (V1)

### A. Core Observability

- Gateway/process health (ready/live/deps)
- Session inventory and active state
- Session history stream (tail + replay)
- Token usage and estimated cost rollups
- Model usage breakdown
- Cron job status/history/next-run
- Sub-agent run tracking

### B. Operations

- Trigger cron jobs
- Pause/resume cron jobs
- Open session drill-down
- Send operator note/action markers
- Safe quick actions (restarts/hooks) via adapter capabilities

### C. Knowledge Surfaces

- Memory file browser (read-only in V1)
- Recent git activity panel
- Alerts engine (threshold/policy driven)

### D. Multi-Interface Experience

- Unified data contract across TUI/Web/McCLIM
- Keyboard-first navigation model shared by TUI + McCLIM
- Same core cards/views available in all three UIs

## Architecture Workstreams

1. **Typed Core Domain**
   - Coalton records/types for normalized entities
   - Functional reducers for metrics and timelines
2. **Adapter SDK**
   - OpenClaw adapter implementation
   - Generic adapter protocol and validation suite
3. **Application Services**
   - Queries, projections, command dispatch
4. **UI Frontends**
   - TUI app package
   - Web server + frontend
   - McCLIM app package
5. **Test & CI Harness**
   - E2E harness with deterministic fixture runtime
   - Multi-UI interaction automation

## Feature Roadmap by Epic

### Epic 1 — Foundation and Type-Safe Core

- Repo structure, package layout, coding standard
- Coalton domain core
- SBCL strict type policies and linters
- Config system and adapter interface skeleton

**Done when:** typed core compiles, adapter conformance tests pass.

### Epic 2 — OpenClaw Adapter + Data Pipeline

- Implement OpenClaw adapter endpoints/parsers
- Build event ingest + normalization pipeline
- Snapshot + incremental update model

**Done when:** fixture + live OpenClaw both produce normalized records; replay deterministic.

### Epic 3 — TUI Operations Console

- Dashboard panels, navigation, filtering, search
- Actions: cron trigger/pause, session drill-down
- Alert banner + activity feed

**Done when:** scripted PTY tests validate real user flows end-to-end.

### Epic 4 — Web Dashboard

- Local web server/API with stream updates
- Dashboard views mirroring TUI capabilities
- Auth/capability boundaries for mutating actions

**Done when:** Playwright suite passes against live app and fixture runtime.

### Epic 5 — McCLIM Interface

- CLIM frame with pane layout matching core observability views
- Command tables + interactive inspectors
- Shared command semantics with TUI/Web

**Done when:** CLIM event-injection tests validate workflows.

### Epic 6 — Cross-UI Parity + Plugin SDK

- Capability parity audit across all interfaces
- Plugin loading for custom cards/adapters
- Adapter author docs + examples for non-OpenClaw systems

**Done when:** parity tests and plugin smoke tests pass for all UIs.

### Epic 7 — Production Hardening

- Performance profiling (high session counts)
- Fault tolerance under adapter failure
- Packaging/systemd/container support
- Release docs and operational runbook

**Done when:** soak + resilience + packaging tests pass in CI.

## Mandatory E2E Quality Gate Rule

No epic may be closed until its E2E tests pass in CI against **real interface interaction**.

- No mock-only closure.
- No unit-test-only closure.
- Must include user-level interactions (terminal keystrokes, browser events, CLIM commands).

See `docs/E2E-MATRIX.md` for exact scenarios.

## Design Documentation Rule (Cross-Repo)

Every implementation bead must explicitly require updating Common Lisp design docs in:

- `/home/slime/projects/emacsen-design-docs`

At minimum each merged feature updates:

- architectural decision notes,
- typed API contracts,
- test evidence summary.

## Initial Milestone Targets

- M0 (2 weeks): Epics 1-2 foundations + adapter ingest
- M1 (3 weeks): TUI + baseline E2E
- M2 (3 weeks): Web + baseline E2E
- M3 (3 weeks): McCLIM + parity E2E
- M4 (2 weeks): hardening + release candidate
