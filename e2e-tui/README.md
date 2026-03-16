# Agent Orrery TUI E2E Tests (mcp-tui-driver)

Deterministic end-to-end test harness for the Agent Orrery terminal UI,
using [mcp-tui-driver](https://github.com/michaellee8/mcp-tui-driver)
as the Playwright-analog for terminal applications.

## Architecture

```
  test-runner (Node.js)
       │
       │ JSON-RPC 2.0 over stdio
       ▼
  mcp-tui-driver (Rust binary)
       │
       │ PTY + terminal emulation (wezterm-term)
       ▼
  sbcl --load start-tui.lisp
       │
       │ croatoan (ncurses)
       ▼
  Agent Orrery TUI Dashboard
```

The test harness communicates with mcp-tui-driver via MCP protocol to:
1. Launch the TUI in a headless PTY
2. Read terminal content as plain text or accessibility snapshots
3. Send keyboard input (keys, text)
4. Capture PNG screenshots and asciicast recordings
5. Wait for screen content or idle states

## Scenarios

| ID | Description | Verifies |
|----|-------------|----------|
| T1 | Dashboard loads with 6 panels | Initial render, panel titles |
| T2 | Panel navigation via number keys | Direct focus (1-6) |
| T3 | Tab cycling through panels | Sequential focus rotation |
| T4 | Help mode toggle | ? → help, Esc → normal |
| T5 | Resize handling | 80×24 ↔ 120×40, panel relayout |
| T6 | Fixture data content verification | Deterministic data from fixture adapter |

## Prerequisites

1. **mcp-tui-driver** binary installed:
   ```bash
   cargo install --git https://github.com/michaellee8/mcp-tui-driver
   # or: cp ~/external_src/mcp-tui-driver/target/release/mcp-tui-driver ~/.local/bin/
   ```

2. **SBCL** with Quicklisp and agent-orrery ASDF system loadable

3. **Node.js** (v18+)

## Run

```bash
# From project root:
make e2e-tui

# Or directly:
./e2e-tui/run-tui-e2e.sh
```

## Artifacts

All artifacts are written to `test-results/tui-artifacts/`:

| File | Description |
|------|-------------|
| `tui-e2e-report.json` | JSON test results |
| `tui-e2e-session.cast` | asciicast recording (play with `asciinema play`) |
| `T*-*.png` | Per-scenario screenshots |
| `T*-*.txt` | Per-scenario terminal transcripts |

## Relation to Web Dashboard E2E

The web dashboard E2E suite (Playwright, `e2e/`) covers scenarios S1-S6
for the HTTP/HTML dashboard. This suite covers analogous scenarios T1-T8
for the terminal-based ncurses dashboard, using mcp-tui-driver instead
of Playwright.

| Web (S*) | TUI (T*) | Shared concept |
|----------|----------|----------------|
| S1: dashboard loads | T1: dashboard loads | Initial render |
| S2: sessions page | T2: panel navigation | Navigation |
| S3: session detail | T3: tab cycling | Focus management |
| S4: cron page | T4: help mode | Mode switching |
| S5: alerts page | T5: resize handling | Viewport adaptation |
| S6: API endpoints | T6: fixture data | Data correctness |
