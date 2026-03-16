# Agent Orrery — Manual UI Testing Quickstart

## Prerequisites
- SBCL installed
- Quicklisp setup file at `~/quicklisp/setup.lisp` (or set `QL_SETUP`)
- Linux dynamic libs available (`/lib/x86_64-linux-gnu`)

## Launch Scripts

### TUI
```bash
./scripts/run-tui.sh
```

Environment overrides:
- `QL_SETUP=/path/to/setup.lisp`
- `LD_LIBRARY_PATH` (auto-prefixed with `/lib/x86_64-linux-gnu`)

### Web UI
```bash
./scripts/run-web.sh
```

Environment overrides:
- `ORRERY_HOST` (default `127.0.0.1`)
- `ORRERY_PORT` (default `7890`)
- `QL_SETUP=/path/to/setup.lisp`

## Smoke-check sequence
1. Run Web script, open `http://127.0.0.1:7890`
2. Verify sessions/cron/health/events/alerts/usage pages load
3. Run TUI script, verify dashboard renders and keybindings respond
4. Run deterministic E2E checks:
   - Web: `cd e2e && bash run-e2e.sh`
   - TUI: `make e2e-tui`
