# Agent Orrery — Packaging & Deployment

This directory contains reproducible build scripts, service recipes, and container definitions for all Agent Orrery distribution targets.

## Targets

| Target | Path | Description |
|--------|------|-------------|
| CLI | `cli/` | Standalone SBCL binary via `sb-ext:save-lisp-and-die` |
| TUI | `tui/` | Terminal UI binary (same approach, loads TUI entry) |
| Web | `web/` | Web server binary + systemd service |
| McCLIM | `mcclim/` | Desktop GUI binary (requires CLX) |
| Container | `container/` | OCI-compatible Dockerfile + compose |
| systemd | `systemd/` | Service unit files for all targets |

## Quick Start

```bash
# Build all targets
make -C packaging all

# Build specific target
make -C packaging cli
make -C packaging web

# Install systemd services
sudo make -C packaging install-services

# Container build + run
make -C packaging container
```
