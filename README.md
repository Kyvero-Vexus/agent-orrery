# Agent Orrery

**Agent Orrery** is a public Kyvero Vexus project to provide a multi-interface operations dashboard for OpenClaw-compatible agent systems.

Like an orrery models celestial bodies from multiple viewpoints, Agent Orrery models agentic runtime state across:

- **Terminal UI (TUI)**
- **Web UI**
- **McCLIM UI**

The platform is OpenClaw-compatible first, but built around a generic adapter protocol so it can support other agentic systems with minimal glue code.

## Core Design Commitments

- **Statically typed Common Lisp**
  - Coalton for pure core logic
  - SBCL strict declarations for integration/runtime layers
- **Functional programming style first** (immutable data flows, pure transforms, side effects at boundaries)
- **Modular architecture** (core domain + adapter boundary + UI frontends)
- **Extensible provider model** (OpenClaw adapter is just the first implementation)
- **E2E test-gated delivery** (every epic must land with real interaction tests)

## Inspiration Sources

- https://github.com/tugcantopaloglu/openclaw-dashboard
- https://github.com/mudrii/openclaw-dashboard
- https://github.com/abhi1693/openclaw-mission-control

## Planning Docs

- Full plan: `docs/PLAN.md`
- E2E matrix: `docs/E2E-MATRIX.md`
- Architecture: `docs/ARCHITECTURE.md`

## Task Tracking

This repository uses **beads (`bd`)** for all issue tracking.

```bash
bd ready --json
```
