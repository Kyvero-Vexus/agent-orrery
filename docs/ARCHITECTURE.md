# Agent Orrery Architecture

## 1. Layered System

```text
+-------------------------------+
| Frontends                     |
|  - TUI (cl-term based)        |
|  - Web (HTTP + WS/SSE)        |
|  - McCLIM                     |
+---------------+---------------+
                |
+---------------v---------------+
| Application Services           |
|  - Query/read models           |
|  - Commands/actions            |
|  - Policy + auth checks        |
+---------------+---------------+
                |
+---------------v---------------+
| Typed Domain Core              |
|  - Coalton domain model        |
|  - Reducers/projections        |
|  - Validation/pure transforms  |
+---------------+---------------+
                |
+---------------v---------------+
| Adapter Boundary               |
|  - OpenClaw adapter            |
|  - Generic agent runtime proto |
|  - Event poll/stream API       |
+---------------+---------------+
                |
+---------------v---------------+
| Runtime Integrations           |
|  - OpenClaw APIs/tools         |
|  - File system/log parsers     |
|  - Git/cron/session hooks      |
+-------------------------------+
```

## 2. Static Typing Policy

- All exported functions must have explicit type declarations.
- Core business logic is implemented in Coalton modules.
- Integration layers use SBCL strict declarations (`declaim`, `ftype`, precise structs/classes).
- CI fails on undeclared public function types in designated packages.

## 3. Extensibility Contract

New runtime compatibility is implemented via `dashboard.adapter` protocol:

- `list-sessions`
- `session-history`
- `list-cron-jobs`
- `run-cron-job`
- `system-health`
- `usage-and-costs`
- `tail-events`

Adapters provide normalized typed records consumed by all UIs.

## 4. UI Composition

All three interfaces use a shared query layer and command dispatcher:

- **TUI**: high-density operations, keyboard-first
- **Web**: remote visibility, drill-down, history charts
- **McCLIM**: interactive CL-native operator console, inspector-heavy workflows

No UI can bypass application services directly.

## 5. Security & Ops

- Default local binding for web server
- Role/capability checks for mutating actions
- Audit stream for all operator actions
- Deterministic test fixture mode (for E2E)
- Optional read-only mode for safe observability environments
