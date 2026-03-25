# Agent Orrery Architecture

## 1. Layered System

```text
+---------------------------------------------------+
| Frontends                                         |
|  - TUI (cl-term / mcp-tui-driver)                 |
|  - Web (HTTP + WS/SSE + Playwright E2E)           |
|  - McCLIM (interactive CL-native console)         |
+------------------------+--------------------------+
                         |
+------------------------v--------------------------+
| Application Services                              |
|  - Query/read models                              |
|  - Commands/actions                               |
|  - Policy + auth checks                           |
+------------------------+--------------------------+
                         |
+------------------------v--------------------------+
| Typed Domain Core (v2 Coalton modules)            |
|  - audit-trail        ← audit-trail-bridge.lisp   |
|  - cost-optimizer     ← cost-optimizer-bridge.lisp|
|  - capacity-planner   ← capacity-planner-bridge.lisp
|  - session-analytics  ← session-analytics-bridge.lisp
|  - anomaly-detector                               |
|  - budget-policy                                  |
|  - notification-routing                           |
|  - scenario-planning                              |
|  - session-lifecycle                              |
|  - usage-analytics                                |
+------------------------+--------------------------+
                         |
+------------------------v--------------------------+
| Adapter Boundary                                  |
|  - OpenClaw adapter                               |
|  - Generic agent runtime protocol                 |
|  - Event poll/stream API                          |
|  - Evidence adapter layer (Epic 3/4 CI gates)     |
+------------------------+--------------------------+
                         |
+------------------------v--------------------------+
| Runtime Integrations                              |
|  - OpenClaw APIs/tools                            |
|  - File system/log parsers                        |
|  - Git/cron/session hooks                         |
+---------------------------------------------------+
```

## 2. v2 Coalton Module Map

The v2 Coalton modules and their CL bridge adapters:

| Module | CL Bridge | Key Responsibilities |
|--------|-----------|---------------------|
| `audit-trail` | `audit-trail-bridge.lisp` | Immutable operator action log, query API |
| `cost-optimizer` | `cost-optimizer-bridge.lisp` | Usage cost analysis, budget allocation |
| `capacity-planner` | `capacity-planner-bridge.lisp` | Session capacity forecasting |
| `session-analytics` | `session-analytics-bridge.lisp` | Per-session metrics, drift detection |
| `anomaly-detector` | — | Statistical outlier detection on usage |
| `budget-policy` | — | Policy enforcement for cost limits |
| `notification-routing` | — | Alert routing to operator surfaces |
| `scenario-planning` | — | Future-state capacity modeling |

### v2 Module Interaction Diagram

```
audit-trail ──────────────────────────────► audit-trail-bridge
     │                                            │
     │ (events)                                   ▼
     ▼                                    CL adapter layer
cost-optimizer ◄──── session-analytics          │
     │                     │                    ▼
     │ (budget signals)     │ (metrics)    Application Services
     ▼                      ▼
capacity-planner ◄────── anomaly-detector
     │
     ▼
scenario-planning
```

## 3. Static Typing Policy

- All exported functions must have explicit type declarations.
- Core business logic is implemented in Coalton modules.
- Integration layers use SBCL strict declarations (`declaim`, `ftype`, precise structs/classes).
- CI enforces: `ci/check-boundary-declarations.lisp` fails on undeclared public function types.
- All new modules require `src/adapter/` CL bridge file with strict `ftype` declaims.

## 4. Extensibility Contract

New runtime compatibility is implemented via `dashboard.adapter` protocol:

- `list-sessions`
- `session-history`
- `list-cron-jobs`
- `run-cron-job`
- `system-health`
- `usage-and-costs`
- `tail-events`

Adapters provide normalized typed records consumed by all UIs.

## 5. UI Composition

All three interfaces use a shared query layer and command dispatcher:

- **TUI**: high-density operations, keyboard-first; E2E via mcp-tui-driver (T1-T6)
- **Web**: remote visibility, drill-down, history charts; E2E via Playwright (S1-S6)
- **McCLIM**: interactive CL-native operator console, inspector-heavy workflows

No UI can bypass application services directly.

## 6. E2E Evidence Policy

Epic 3 (TUI) and Epic 4 (Web) have machine-enforced evidence gates:

- **Epic 3**: mcp-tui-driver required; T1-T6 asciicast artifacts required; command: `cd e2e-tui && ./run-tui-e2e-t1-t6.sh`
- **Epic 4**: Playwright required; S1-S6 screenshot+trace required; command: `cd e2e && ./run-e2e.sh`
- CI checkers: `ci/check-tui-continuity-preflight.lisp`, `ci/check-playwright-artifact-canonicalizer.lisp`, `ci/check-unified-closure-gate.lisp`
- **Neither epic is complete without real E2E artifacts from a live run.**

## 7. Security & Ops

- Default local binding for web server
- Role/capability checks for mutating actions
- Audit stream for all operator actions (via `audit-trail` module)
- Deterministic test fixture mode (for E2E)
- Optional read-only mode for safe observability environments
