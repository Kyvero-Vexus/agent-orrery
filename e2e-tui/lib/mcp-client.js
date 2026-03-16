#!/usr/bin/env node
// -*- mode: javascript -*-
//
// mcp-client.js — Lightweight JSON-RPC 2.0 client for mcp-tui-driver
//
// Communicates over stdio with the mcp-tui-driver binary.
// Provides a promise-based API for TUI E2E test scenarios.

'use strict';

const { spawn } = require('child_process');
const path = require('path');
const readline = require('readline');

class McpTuiClient {
  constructor(binaryPath) {
    this.binaryPath = binaryPath || 'mcp-tui-driver';
    this.proc = null;
    this.nextId = 1;
    this.pending = new Map(); // id -> { resolve, reject, timer }
    this.rl = null;
  }

  /** Start the mcp-tui-driver process and initialize MCP handshake. */
  async start() {
    this.proc = spawn(this.binaryPath, [], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, RUST_LOG: 'warn' },
    });

    this.rl = readline.createInterface({ input: this.proc.stdout });
    this.rl.on('line', (line) => this._handleLine(line));

    this.proc.stderr.on('data', (chunk) => {
      // Suppress debug noise; log errors only
      const msg = chunk.toString().trim();
      if (msg && /error|panic/i.test(msg)) {
        process.stderr.write(`[mcp-tui-driver stderr] ${msg}\n`);
      }
    });

    this.proc.on('exit', (code) => {
      // Reject all pending
      for (const [id, p] of this.pending) {
        clearTimeout(p.timer);
        p.reject(new Error(`mcp-tui-driver exited with code ${code}`));
      }
      this.pending.clear();
    });

    // MCP initialize handshake (protocol version 2024-11-05)
    const initResult = await this.call('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'agent-orrery-e2e', version: '0.1.0' },
    });

    // Send initialized notification (no id, no response expected)
    const notification = JSON.stringify({
      jsonrpc: '2.0',
      method: 'notifications/initialized',
      params: {},
    });
    this.proc.stdin.write(notification + '\n');

    return initResult;
  }

  /** Send a JSON-RPC request and return the result (or throw on error). */
  call(method, params, timeoutMs = 30000) {
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Timeout waiting for response to ${method} (id=${id})`));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });

      const msg = JSON.stringify({
        jsonrpc: '2.0',
        id,
        method,
        params: params || {},
      });

      this.proc.stdin.write(msg + '\n');
    });
  }

  /** Call an MCP tool by name. */
  async callTool(toolName, args = {}, timeoutMs = 30000) {
    const result = await this.call(
      'tools/call',
      { name: toolName, arguments: args },
      timeoutMs
    );
    // MCP tool results come wrapped in content array
    if (result && result.content && Array.isArray(result.content)) {
      const textContent = result.content.find((c) => c.type === 'text');
      if (textContent) {
        try {
          return JSON.parse(textContent.text);
        } catch {
          return textContent.text;
        }
      }
      const imgContent = result.content.find((c) => c.type === 'image');
      if (imgContent) return imgContent;
    }
    return result;
  }

  // ---- High-level helpers ----

  async launch(command, args = [], opts = {}) {
    return this.callTool('tui_launch', {
      command,
      args,
      cols: opts.cols || 120,
      rows: opts.rows || 40,
      cwd: opts.cwd,
      env: opts.env,
      recording: opts.recording,
    });
  }

  async text(sessionId) {
    return this.callTool('tui_text', { session_id: sessionId });
  }

  async snapshot(sessionId) {
    return this.callTool('tui_snapshot', { session_id: sessionId });
  }

  async screenshot(sessionId) {
    return this.callTool('tui_screenshot', { session_id: sessionId });
  }

  async pressKey(sessionId, key) {
    return this.callTool('tui_press_key', { session_id: sessionId, key });
  }

  async pressKeys(sessionId, keys) {
    return this.callTool('tui_press_keys', { session_id: sessionId, keys });
  }

  async sendText(sessionId, text) {
    return this.callTool('tui_send_text', { session_id: sessionId, text });
  }

  async waitForText(sessionId, text, timeoutMs = 10000) {
    return this.callTool(
      'tui_wait_for_text',
      { session_id: sessionId, text, timeout_ms: timeoutMs },
      timeoutMs + 5000
    );
  }

  async waitForIdle(sessionId, idleMs = 200, timeoutMs = 10000) {
    return this.callTool(
      'tui_wait_for_idle',
      { session_id: sessionId, idle_ms: idleMs, timeout_ms: timeoutMs },
      timeoutMs + 5000
    );
  }

  async close(sessionId) {
    return this.callTool('tui_close', { session_id: sessionId });
  }

  async resize(sessionId, cols, rows) {
    return this.callTool('tui_resize', {
      session_id: sessionId,
      cols,
      rows,
    });
  }

  /** Stop the mcp-tui-driver process. */
  async stop() {
    if (this.rl) this.rl.close();
    if (this.proc) {
      this.proc.stdin.end();
      this.proc.kill('SIGTERM');
      await new Promise((res) =>
        this.proc.once('exit', res)
      );
    }
  }

  // ---- Internal ----

  _handleLine(line) {
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      return; // skip non-JSON lines (e.g. logs)
    }
    if (msg.id != null && this.pending.has(msg.id)) {
      const p = this.pending.get(msg.id);
      this.pending.delete(msg.id);
      clearTimeout(p.timer);
      if (msg.error) {
        p.reject(new Error(`MCP error ${msg.error.code}: ${msg.error.message}`));
      } else {
        p.resolve(msg.result);
      }
    }
  }
}

module.exports = { McpTuiClient };
