#!/usr/bin/env node
// -*- mode: javascript -*-
//
// test-runner.js — Minimal deterministic test runner for TUI E2E scenarios
//
// Runs scenarios sequentially, captures artifacts, reports pass/fail.

'use strict';

const fs = require('fs');
const path = require('path');

const ARTIFACTS_DIR = path.resolve(__dirname, '../../test-results/tui-artifacts');

class TestRunner {
  constructor() {
    this.results = [];
    this.currentScenario = null;
  }

  /** Register and run a scenario function. */
  async run(name, fn) {
    this.currentScenario = name;
    const startMs = Date.now();
    const result = { name, status: 'PASS', error: null, durationMs: 0, artifacts: [] };

    try {
      await fn();
    } catch (err) {
      result.status = 'FAIL';
      result.error = err.message || String(err);
    }

    result.durationMs = Date.now() - startMs;
    this.results.push(result);

    const icon = result.status === 'PASS' ? '✓' : '✗';
    const color = result.status === 'PASS' ? '\x1b[32m' : '\x1b[31m';
    process.stdout.write(
      `  ${color}${icon}\x1b[0m ${name} (${result.durationMs}ms)` +
        (result.error ? ` — ${result.error}` : '') +
        '\n'
    );

    this.currentScenario = null;
    return result;
  }

  /** Save a base64 PNG screenshot artifact. */
  saveScreenshot(name, base64Data) {
    if (!fs.existsSync(ARTIFACTS_DIR)) fs.mkdirSync(ARTIFACTS_DIR, { recursive: true });
    const fname = `${name}.png`;
    const fpath = path.join(ARTIFACTS_DIR, fname);
    fs.writeFileSync(fpath, Buffer.from(base64Data, 'base64'));
    const scenario = this.results[this.results.length - 1] || {};
    if (scenario.artifacts) scenario.artifacts.push(fpath);
    return fpath;
  }

  /** Save a text transcript artifact. */
  saveTranscript(name, text) {
    if (!fs.existsSync(ARTIFACTS_DIR)) fs.mkdirSync(ARTIFACTS_DIR, { recursive: true });
    const fname = `${name}.txt`;
    const fpath = path.join(ARTIFACTS_DIR, fname);
    fs.writeFileSync(fpath, text, 'utf8');
    const scenario = this.results[this.results.length - 1] || {};
    if (scenario.artifacts) scenario.artifacts.push(fpath);
    return fpath;
  }

  /** Print summary and return exit code. */
  summary() {
    const passed = this.results.filter((r) => r.status === 'PASS').length;
    const failed = this.results.filter((r) => r.status === 'FAIL').length;
    const total = this.results.length;

    process.stdout.write(
      `\n  ${passed}/${total} passed` +
        (failed > 0 ? `, \x1b[31m${failed} failed\x1b[0m` : '') +
        '\n'
    );

    // Save JSON report
    const reportPath = path.join(ARTIFACTS_DIR, 'tui-e2e-report.json');
    fs.writeFileSync(reportPath, JSON.stringify(this.results, null, 2));
    process.stdout.write(`  Report: ${reportPath}\n`);

    return failed > 0 ? 1 : 0;
  }
}

module.exports = { TestRunner, ARTIFACTS_DIR };
