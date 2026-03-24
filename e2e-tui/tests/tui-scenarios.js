#!/usr/bin/env node
// -*- mode: javascript -*-
//
// tui-scenarios.js — T1-T8 deterministic TUI E2E scenarios
//
// Uses mcp-tui-driver to launch the Agent Orrery TUI (ncurses dashboard),
// navigate panels, verify content, and capture artifacts.
//
// Analogous to e2e/tests/dashboard.spec.ts (S1-S6) but for terminal UI.
//
// Run:
//   node e2e-tui/tests/tui-scenarios.js
//   # or via wrapper:
//   ./e2e-tui/run-tui-e2e.sh
//
// Precompiled core (optional, recommended):
//   Run ./scripts/build-tui-core.sh to create artifacts/tui-core.core.
//   Set ORRERY_TUI_CORE env var to use it (default: artifacts/tui-core.core).
//   Reduces startup from ~31s to <5s.

'use strict';

const path = require('path');
const fs = require('fs');
const { McpTuiClient } = require('../lib/mcp-client');
const { TestRunner } = require('../lib/test-runner');

const PROJECT_ROOT = path.resolve(__dirname, '../..');
const RECORDING_DIR = path.resolve(PROJECT_ROOT, 'test-results/tui-artifacts');
const SCENARIO_FILTER = process.env.SCENARIO_FILTER || 'ALL';

// Check for precompiled core (fast startup)
const CORE_PATH = process.env.ORRERY_TUI_CORE || path.join(PROJECT_ROOT, 'artifacts/tui-core.core');
const USE_CORE = fs.existsSync(CORE_PATH);

let TUI_LAUNCH_CMD = 'sbcl';
let TUI_LAUNCH_ARGS;
if (USE_CORE) {
  // Fast path: use precompiled core
  TUI_LAUNCH_ARGS = [
    '--core', CORE_PATH,
    '--eval', '(orrery/tui-core:launch-dashboard)',
  ];
} else {
  // Slow path: load from source
  TUI_LAUNCH_ARGS = ['--load', path.join(PROJECT_ROOT, 'e2e-tui/start-tui.lisp')];
}

// Assertion helper
function assert(condition, msg) {
  if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function parseScenarioFilter() {
  if (SCENARIO_FILTER.toUpperCase() === 'ALL') return null;
  return new Set(
    SCENARIO_FILTER.split(',')
      .map((s) => s.trim().toUpperCase())
      .filter(Boolean)
  );
}

async function main() {
  const client = new McpTuiClient();
  const runner = new TestRunner();
  const selected = parseScenarioFilter();
  const shouldRun = (id) => !selected || selected.has(id.toUpperCase());
  const runScenario = async (id, name, fn) => {
    if (!shouldRun(id)) {
      console.log(`  - SKIP ${id}: filtered`);
      return;
    }
    await runner.run(name, fn);
  };
  let sessionId = null;

  console.log('\n=== Agent Orrery TUI E2E (mcp-tui-driver) ===');
  if (USE_CORE) {
    console.log(`  Using precompiled core: ${CORE_PATH} (fast startup)`);
  } else {
    console.log('  Loading from source (slow startup)');
    console.log('  TIP: Run scripts/build-tui-core.sh for fast startup');
  }
  console.log();

  try {
    // Start MCP driver
    await client.start();

    // Launch TUI with recording enabled
    if (!fs.existsSync(RECORDING_DIR)) fs.mkdirSync(RECORDING_DIR, { recursive: true });

    const launchResult = await client.launch(TUI_LAUNCH_CMD, TUI_LAUNCH_ARGS, {
      cols: 120,
      rows: 40,
      cwd: PROJECT_ROOT,
      recording: {
        enabled: true,
        outputPath: path.join(RECORDING_DIR, 'tui-e2e-session.cast'),
        includeInput: true,
      },
    });
    sessionId = launchResult.session_id;
    assert(sessionId, 'got session_id from launch');

    // Wait for TUI to initialize (look for panel titles)
    // System load time grows with module count; 60s accommodates cold Coalton compile
    await client.waitForText(sessionId, 'Sessions (1)', 60000);
    // Extra settle time for full render
    await client.waitForIdle(sessionId, 1000, 10000);

    // ================================================================
    // T1: Dashboard loads, all 6 panels visible
    // ================================================================
    await runScenario('T1', 'T1: dashboard loads with 6 panels', async () => {
      const screen = await client.text(sessionId);
      const screenText = typeof screen === 'object' ? screen.text : screen;

      runner.saveTranscript('T1-initial-load', screenText);

      // All panel titles must be present
      assert(screenText.includes('Sessions (1)'), 'Sessions panel visible');
      assert(screenText.includes('Cron (2)'), 'Cron panel visible');
      assert(screenText.includes('Health (3)'), 'Health panel visible');
      assert(screenText.includes('Events (4)'), 'Events panel visible');
      assert(screenText.includes('Alerts (5)'), 'Alerts panel visible');
      assert(screenText.includes('Usage (6)'), 'Usage panel visible');

      // Capture screenshot
      const shot = await client.screenshot(sessionId);
      if (shot && shot.data) runner.saveScreenshot('T1-initial-load', shot.data);
    });

    // ================================================================
    // T2: Panel navigation via number keys (1-6)
    // ================================================================
    await runScenario('T2', 'T2: panel navigation via number keys', async () => {
      // Press '2' to focus Cron panel
      await client.pressKey(sessionId, '2');
      await client.waitForIdle(sessionId, 300, 3000);
      let screen = await client.text(sessionId);
      let screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T2-focus-cron', screenText);

      // Press '5' to focus Alerts panel
      await client.pressKey(sessionId, '5');
      await client.waitForIdle(sessionId, 300, 3000);
      screen = await client.text(sessionId);
      screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T2-focus-alerts', screenText);

      // Press '1' to go back to Sessions
      await client.pressKey(sessionId, '1');
      await client.waitForIdle(sessionId, 300, 3000);
      screen = await client.text(sessionId);
      screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T2-focus-sessions', screenText);

      // All navigations completed without crash — pass
      assert(screenText.includes('Sessions (1)'), 'back on sessions panel');

      const shot = await client.screenshot(sessionId);
      if (shot && shot.data) runner.saveScreenshot('T2-panel-nav', shot.data);
    });

    // ================================================================
    // T3: Tab cycling through panels
    // ================================================================
    await runScenario('T3', 'T3: tab cycling through panels', async () => {
      // Start from known state
      await client.pressKey(sessionId, '1');
      await client.waitForIdle(sessionId, 200, 2000);

      // Tab through all 6 panels
      const transcripts = [];
      for (let i = 0; i < 6; i++) {
        await client.pressKey(sessionId, 'Tab');
        await client.waitForIdle(sessionId, 200, 2000);
        const screen = await client.text(sessionId);
        const screenText = typeof screen === 'object' ? screen.text : screen;
        transcripts.push(screenText);
      }

      // After 6 tabs we should cycle back to original
      // Save combined transcript
      runner.saveTranscript('T3-tab-cycle', transcripts.join('\n--- TAB ---\n'));

      // Each transcript should still show the dashboard (not crash)
      for (const t of transcripts) {
        assert(t.length > 50, 'screen has content after tab');
      }

      const shot = await client.screenshot(sessionId);
      if (shot && shot.data) runner.saveScreenshot('T3-tab-cycle', shot.data);
    });

    // ================================================================
    // T4: Help mode toggle
    // ================================================================
    await runScenario('T4', 'T4: help mode toggle', async () => {
      // Press '?' to enter help mode
      await client.pressKey(sessionId, '?');
      // Give TUI time to process input and re-render
      await new Promise((r) => setTimeout(r, 500));
      await client.waitForIdle(sessionId, 300, 5000);
      let screen = await client.text(sessionId);
      let screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T4-help-mode', screenText);

      // Help message or HELP mode indicator should be visible
      assert(
        screenText.includes('HELP') || screenText.includes('exit help'),
        'help mode activated'
      );

      // Press Escape to return to normal mode
      // ncurses has ~1s escape delay for disambiguating escape sequences
      await client.pressKey(sessionId, 'Escape');
      await new Promise((r) => setTimeout(r, 2000));
      await client.waitForIdle(sessionId, 300, 3000);
      screen = await client.text(sessionId);
      screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T4-normal-mode', screenText);

      // Should be back in NORMAL mode
      assert(screenText.includes('NORMAL'), 'back to normal mode');

      const shot = await client.screenshot(sessionId);
      if (shot && shot.data) runner.saveScreenshot('T4-help-toggle', shot.data);
    });

    // ================================================================
    // T5: Resize handling
    // ================================================================
    await runScenario('T5', 'T5: resize handling', async () => {
      // Resize to smaller terminal
      await client.resize(sessionId, 80, 24);
      // Give croatoan time to process SIGWINCH and re-render
      await new Promise((r) => setTimeout(r, 1000));
      await client.waitForIdle(sessionId, 500, 5000);
      let screen = await client.text(sessionId);
      let screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T5-resize-80x24', screenText);

      // After resize, screen should have content (not crash)
      // Panel titles may be truncated at 80 cols but should still be present
      assert(
        screenText.includes('Sessions') || screenText.includes('Cron') || screenText.length > 100,
        'panels visible after shrink'
      );

      // Resize back to large
      await client.resize(sessionId, 120, 40);
      await new Promise((r) => setTimeout(r, 1000));
      await client.waitForIdle(sessionId, 500, 5000);
      screen = await client.text(sessionId);
      screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T5-resize-120x40', screenText);

      assert(
        screenText.includes('Sessions') || screenText.length > 200,
        'panels visible after grow'
      );

      const shot = await client.screenshot(sessionId);
      if (shot && shot.data) runner.saveScreenshot('T5-resize', shot.data);
    });

    // ================================================================
    // T6: Fixture data content verification
    // ================================================================
    await runScenario('T6', 'T6: fixture data content verification', async () => {
      // Focus Sessions panel and check for fixture session data
      await client.pressKey(sessionId, '1');
      await client.waitForIdle(sessionId, 300, 3000);

      const screen = await client.text(sessionId);
      const screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T6-fixture-data', screenText);

      // The fixture adapter should produce deterministic session data
      // At minimum the screen must have structured content beyond just borders
      const lines = screenText.split('\n').filter((l) => l.trim().length > 0);
      assert(lines.length > 10, 'screen has substantive content from fixture data');

      // Capture final accessibility snapshot
      const snap = await client.snapshot(sessionId);
      if (snap) {
        const snapText = typeof snap === 'object' ? JSON.stringify(snap, null, 2) : snap;
        runner.saveTranscript('T6-accessibility-snapshot', snapText);
      }

      const shot = await client.screenshot(sessionId);
      if (shot && shot.data) runner.saveScreenshot('T6-fixture-data', shot.data);
    });

    // ================================================================
    // T7: Analytics expansion flow remains stable in Usage pane
    // ================================================================
    await runScenario('T7', 'T7: analytics expansion flow stable', async () => {
      // Focus Usage panel and exercise rapid re-focus to stress analytics rendering
      await client.pressKey(sessionId, '6');
      await client.waitForIdle(sessionId, 300, 3000);
      await client.pressKey(sessionId, '1');
      await client.waitForIdle(sessionId, 200, 2000);
      await client.pressKey(sessionId, '6');
      await client.waitForIdle(sessionId, 300, 3000);

      const screen = await client.text(sessionId);
      const screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T7-analytics-expansion', screenText);

      // Usage pane should be present and non-empty after analytics expansion changes
      assert(screenText.includes('Usage (6)'), 'Usage pane visible');
      assert(screenText.includes('Model') || screenText.length > 200, 'usage table content visible');

      const shot = await client.screenshot(sessionId);
      if (shot && shot.data) runner.saveScreenshot('T7-analytics-expansion', shot.data);
    });

    // ================================================================
    // T8: Audit/capacity flow remains stable under rapid pane switching
    // ================================================================
    await runScenario('T8', 'T8: rapid pane switching stability', async () => {
      const sequence = ['1', '6', '2', '5', '6', '1', '3', '4'];
      for (const key of sequence) {
        await client.pressKey(sessionId, key);
        await client.waitForIdle(sessionId, 150, 2000);
      }

      const screen = await client.text(sessionId);
      const screenText = typeof screen === 'object' ? screen.text : screen;
      runner.saveTranscript('T8-rapid-switch', screenText);

      // Should still be alive and rendering dashboard structure
      assert(screenText.includes('Sessions') || screenText.includes('Usage'), 'dashboard still rendered');
      assert(screenText.length > 100, 'screen non-empty after rapid switching');

      const shot = await client.screenshot(sessionId);
      if (shot && shot.data) runner.saveScreenshot('T8-rapid-switch', shot.data);
    });
  } catch (err) {
    console.error(`\n  Fatal error: ${err.message}\n`);
    process.exitCode = 1;
  } finally {
    // Cleanup: close TUI session, stop driver
    if (sessionId) {
      try {
        await client.pressKey(sessionId, 'q'); // graceful quit
        await new Promise((r) => setTimeout(r, 1000));
      } catch {}
      try {
        await client.close(sessionId);
      } catch {}
    }
    await client.stop();
  }

  process.exitCode = runner.summary();
}

main();
