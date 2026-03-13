# Agent Orrery E2E Test Matrix

All scenarios must run against:

1. deterministic fixture runtime
2. live OpenClaw-compatible runtime (where safe)

## Test Harness Components

- `test-harness/runtime-fixture` — fake adapter backend with deterministic timelines
- `test-harness/openclaw-fixture` — scripted OpenClaw test workspace setup
- `test-harness/pty` — terminal automation for TUI (Expect/PTY driver)
- `test-harness/web` — Playwright tests for browser workflows
- `test-harness/mcclim` — CLIM event injector + assertion harness

## Core Scenario IDs

### S1: Health + Session Snapshot

- Open dashboard
- Verify gateway health card
- Verify active session table appears
- Verify model + token fields populated

**Applies to:** TUI, Web, McCLIM

### S2: Session Drill-Down and History

- Select session from list
- Open detail pane/page
- Verify message timeline loads and updates
- Apply filter/search and confirm reduced result set

**Applies to:** TUI, Web, McCLIM

### S3: Cron Operations

- Open cron panel
- Trigger a cron job manually
- Observe run state transition (queued/running/success)
- Pause/resume eligible cron

**Applies to:** TUI, Web, McCLIM

### S4: Cost + Usage Analytics

- Load usage dashboard
- Switch window (24h/7d/30d)
- Validate per-model totals and trend chart values

**Applies to:** TUI, Web, McCLIM

### S5: Sub-Agent Monitoring

- Spawn sub-agent in fixture
- Confirm appearance in activity feed
- Open run details and verify status/duration/tokens

**Applies to:** TUI, Web, McCLIM

### S6: Alert Engine

- Inject threshold breach event
- Verify alert appears with severity
- Acknowledge/snooze alert
- Verify audit log entry exists

**Applies to:** TUI, Web, McCLIM

### S7: Adapter Failover Resilience

- Simulate adapter timeout/error burst
- Verify degraded-state banner
- Verify recovery when adapter restores

**Applies to:** TUI, Web, McCLIM

### S8: Plugin Card Lifecycle

- Load sample plugin card
- Verify render + data binding
- Disable plugin and verify UI cleanup

**Applies to:** TUI, Web, McCLIM

## Epic-to-Test Coverage

- Epic 1: Harness bootstrap + typed conformance tests
- Epic 2: S1 + adapter ingest/replay invariants
- Epic 3: S1/S2/S3/S4/S5 via PTY automation
- Epic 4: S1/S2/S3/S4/S5/S6 via Playwright
- Epic 5: S1/S2/S3/S4/S5/S6 via CLIM event harness
- Epic 6: S7/S8 + cross-UI parity assertions
- Epic 7: all S1-S8 under soak/fault profiles

## CI Gates

A PR touching a closed epic boundary must include:

1. E2E artifacts (logs/screenshots/recordings)
2. Passing scenario set required for that epic
3. Design-doc update in `emacsen-design-docs` linked in PR

No exceptions.
