# Agent Orrery — Operator Runbook

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Starting the Service](#starting-the-service)
5. [Upgrade Procedure](#upgrade-procedure)
6. [Rollback Procedure](#rollback-procedure)
7. [Health Checks](#health-checks)
8. [Troubleshooting](#troubleshooting)
9. [Observability](#observability)
10. [Release Checklist](#release-checklist)

---

## Prerequisites

| Component | Minimum Version | Notes |
|-----------|----------------|-------|
| SBCL | 2.5.x | Required for all targets |
| Quicklisp | Latest | CL dependency manager |
| Node.js | 22.x | Web E2E / Playwright only |
| Docker | 24.x | Container deployment only |
| systemd | 250+ | Service management |

```bash
# Verify prerequisites
sbcl --version
node --version   # optional, web only
docker --version # optional, container only
```

## Installation

### From Source

```bash
git clone https://github.com/Kyvero-Vexus/agent-orrery.git
cd agent-orrery

# Run tests to verify build
export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
sbcl --eval '(load "~/quicklisp/setup.lisp")' --script ci/run-tests.lisp

# Build binaries
cd packaging && make all
```

### Container

```bash
cd packaging
docker build -t agent-orrery:latest -f Dockerfile ..
```

### systemd

```bash
sudo cp packaging/systemd/agent-orrery-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable agent-orrery-web
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ORRERY_PORT` | `7890` | Web server port |
| `ORRERY_HOST` | `127.0.0.1` | Bind address |
| `LD_LIBRARY_PATH` | — | Must include `/lib/x86_64-linux-gnu` for CFFI |

Configuration is validated at startup via the typed configuration schema (see `src/coalton/configuration.lisp`). Invalid config causes a clean abort with diagnostic output.

## Starting the Service

### Direct

```bash
export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
sbcl --eval '(load "~/quicklisp/setup.lisp")' \
     --eval '(asdf:load-system "agent-orrery")' \
     --eval '(orrery/web:main)'
```

### systemd

```bash
sudo systemctl start agent-orrery-web
sudo systemctl status agent-orrery-web
journalctl -u agent-orrery-web -f
```

### Container

```bash
docker compose -f packaging/docker-compose.yml up -d
docker compose -f packaging/docker-compose.yml logs -f
```

## Upgrade Procedure

1. **Backup current state:**
   ```bash
   git stash  # if local modifications
   git tag pre-upgrade-$(date +%Y%m%d%H%M)
   ```

2. **Pull and verify:**
   ```bash
   git pull origin master
   make ci  # run full CI gate locally
   ```

3. **Stop service:**
   ```bash
   sudo systemctl stop agent-orrery-web
   ```

4. **Rebuild:**
   ```bash
   cd packaging && make web
   ```

5. **Restart:**
   ```bash
   sudo systemctl start agent-orrery-web
   ```

6. **Verify health:**
   ```bash
   curl -f http://localhost:7890/health
   journalctl -u agent-orrery-web --since "1 min ago"
   ```

## Rollback Procedure

1. **Stop service:**
   ```bash
   sudo systemctl stop agent-orrery-web
   ```

2. **Revert to tagged version:**
   ```bash
   git checkout pre-upgrade-YYYYMMDDHHMI
   cd packaging && make web
   ```

3. **Restart and verify:**
   ```bash
   sudo systemctl start agent-orrery-web
   curl -f http://localhost:7890/health
   ```

## Health Checks

### HTTP (Web target)

```bash
curl -f http://localhost:7890/health
# Expected: {"status":"ok","components":[...]}
```

### Programmatic

```lisp
;; In SBCL REPL
(asdf:load-system "agent-orrery")
(let ((adapter (orrery/harness:make-fixture-adapter)))
  (orrery/adapter:adapter-system-health adapter))
```

### systemd Watchdog

The web service unit includes `Restart=on-failure` with 5-second backoff. Docker compose includes a 30-second health check interval.

## Troubleshooting

### SBCL won't load system

**Symptom:** `Package does not exist` or `System not found` errors.

**Fix:**
```bash
# Ensure Quicklisp can find the project
sbcl --eval '(load "~/quicklisp/setup.lisp")' \
     --eval '(push #p"/path/to/agent-orrery/" asdf:*central-registry*)' \
     --eval '(asdf:load-system "agent-orrery")'
```

### CFFI / FFI library errors

**Symptom:** `Unable to load foreign library` or `libssl` errors.

**Fix:**
```bash
export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
```

### Coalton compilation slow

**Symptom:** First load takes >60 seconds due to Coalton type checking.

**Expected behavior.** Coalton performs full type inference on first load. Subsequent loads use cached FASLs. Pre-compile with:
```bash
sbcl --eval '(load "~/quicklisp/setup.lisp")' \
     --eval '(asdf:load-system "agent-orrery/coalton")' \
     --quit
```

### Tests fail with wrong count

**Symptom:** Test count doesn't match expected (e.g., 2403).

**Fix:** Ensure all `.asd` components are listed and ASDF cache is fresh:
```bash
rm -rf ~/.cache/common-lisp/
make test
```

### Port already in use

**Symptom:** `Address already in use` on port 7890.

**Fix:**
```bash
lsof -i :7890
kill <PID>  # or change ORRERY_PORT
```

### v2 Module Troubleshooting (Epic 10)

#### Cost optimizer returns unexpected model

**Symptom:** Recommendation appears counterintuitive.

**Checks:**
1. Verify strategy (`cost|quality|balanced|latency`) used by caller
2. Verify model cost profile rates (prompt/completion per 1k)
3. Verify entry volume (confidence low under sparse history)

**REPL diagnosis:**
```lisp
(let* ((profiles (list ...))
       (entries (list ...))
       (rec (orrery/coalton/core:cl-recommend-model profiles entries
               (orrery/coalton/core:cl-opt-balanced))))
  (list (orrery/coalton/core:cl-rr-model rec)
        (orrery/coalton/core:cl-rr-confidence-label rec)
        (orrery/coalton/core:cl-rr-strategy-label rec)))
```

#### Capacity planner reports `overflow`

**Symptom:** Capacity zone is critical/overflow unexpectedly.

**Checks:**
1. Validate threshold specs (warning/critical/max values)
2. Confirm metric inputs are per-hour normalized
3. Ensure cost/tokens units match expected scale

**REPL diagnosis:**
```lisp
(let* ((thresholds (orrery/coalton/core:cl-default-capacity-thresholds))
       (values (list sessions tokens-per-hour cost-per-hour cron-per-hour))
       (plan (orrery/coalton/core:cl-build-capacity-plan thresholds values)))
  (list (orrery/coalton/core:cl-plan-worst-zone-label plan)
        (orrery/coalton/core:cl-plan-headroom-pct plan)))
```

#### Session analytics bucket counts look wrong

**Symptom:** Duration histogram seems inconsistent.

**Checks:**
1. Durations must be seconds (not milliseconds)
2. Bucket boundaries are: `<1m`, `1-5m`, `5-15m`, `15-60m`, `>60m`
3. Verify session metric construction before analysis

#### Audit trail hash chain mismatch

**Symptom:** Audit entry hash/prev-hash continuity breaks.

**Checks:**
1. Use a deterministic hash function in test/staging
2. Ensure entries are appended in sequence order
3. Verify previous trail state is passed into entry creation

#### Projection bridge pagination inconsistency

**Symptom:** UI pages skip/duplicate rows.

**Checks:**
1. Confirm `offset` and `limit` are deterministic and stable
2. Use typed `page-request` + `paginate-items` from `v2-projection-bridge`
3. Ensure sort key/order are fixed per endpoint

## Observability

### Anomaly Detection

The typed anomaly detector (`src/coalton/anomaly-detector.lisp`) provides automated detection of:
- Session count drift
- Cost runaway
- Token spikes
- Model routing shifts
- Adapter divergence

Run from REPL:
```lisp
(let ((thresholds (orrery/coalton/core:cl-default-thresholds)))
  (orrery/coalton/core:cl-detect-session-drift thresholds 150 100))
```

### Performance Profiling

The soak harness profiles pipeline throughput:
```lisp
(let* ((cfg (orrery/adapter:make-soak-profile-config :medium))
       (report (orrery/adapter:run-soak-suite cfg :timestamp (get-universal-time))))
  (format t "~A~%" (orrery/adapter:soak-report->json report)))
```

### Notification Routing

Alerts are routed through the typed notification dispatcher:
```lisp
(orrery/coalton/core:cl-dispatch-notification event config seen-set)
```

### Resilience Validation

Run the resilience suite to verify fault recovery paths:
```lisp
(let ((report (orrery/adapter:run-resilience-suite
               (orrery/adapter:make-default-resilience-scenarios)
               :timestamp (get-universal-time))))
  (format t "~A~%" (orrery/adapter:resilience-report->json report)))
```

## Release Checklist

- [ ] All tests pass: `make ci` → PASSED
- [ ] Type policy enforced: `make check-types` → PASSED
- [ ] Resilience suite green: 7/7 scenarios pass
- [ ] Soak test passes at `:medium` profile minimum
- [ ] E2E Web: Playwright S1-S6 pass with screenshot + trace artifacts
- [ ] E2E TUI: mcp-tui-driver T1-T6 pass with PNG + TXT + cast + JSON artifacts
- [ ] Design docs updated in `emacsen-design-docs/agent-orrery/`
- [ ] CHANGELOG updated
- [ ] Version tag created: `git tag vX.Y.Z`
- [ ] Pushed to remote: `git push origin master --tags`
- [ ] Container image rebuilt and tested
- [ ] systemd service restarted and health check passes
