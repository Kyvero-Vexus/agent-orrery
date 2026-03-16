/**
 * TUI Driver — mcp-tui-driver compatible harness using node-pty.
 * Provides: launch, readScreen, sendKeys, waitForText, captureArtifact.
 * When mcp-tui-driver binary is available, swap transport layer only.
 */
import pty from 'node-pty';
import fs from 'fs';
import path from 'path';

export class TuiDriver {
  constructor() {
    this.term = null;
    this.buffer = '';
    this.artifactDir = path.join(process.cwd(), 'test-results');
  }

  async launch(cmd, args = [], opts = {}) {
    fs.mkdirSync(this.artifactDir, { recursive: true });
    const cols = opts.cols || 120;
    const rows = opts.rows || 40;
    this.term = pty.spawn(cmd, args, {
      name: 'xterm-256color',
      cols, rows,
      cwd: opts.cwd || process.cwd(),
      env: { ...process.env, ...(opts.env || {}) },
    });
    this.buffer = '';
    this.term.onData((data) => { this.buffer += data; });
    // Wait for initial render
    await this.sleep(opts.startupMs || 2000);
  }

  readScreen() {
    // Strip ANSI/VT escape codes for text assertions
    return this.buffer
      .replace(/\x1b\[[0-9;]*[A-Za-z]/g, '')   // CSI sequences
      .replace(/\x1b\][^\x07]*\x07/g, '')       // OSC sequences
      .replace(/\x1b[()][0-9A-B]/g, '')         // Character set
      .replace(/\x1b[=>]/g, '')                  // Keypad modes
      .replace(/\x1b\?[0-9;]*[a-z]/g, '')       // Private modes
      .replace(/\x1b\[[\?]?[0-9;]*[a-z]/g, '')  // Extended CSI
      .replace(/[\x00-\x08\x0e-\x1f]/g, '');    // Control chars (keep \t \n \r)
  }

  rawScreen() {
    return this.buffer;
  }

  sendKeys(keys) {
    if (this.term) this.term.write(keys);
  }

  async waitForText(text, timeoutMs = 5000) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      if (this.readScreen().includes(text)) return true;
      await this.sleep(100);
    }
    return false;
  }

  async waitForIdle(idleMs = 500, timeoutMs = 5000) {
    const start = Date.now();
    let lastLen = this.buffer.length;
    let idleStart = Date.now();
    while (Date.now() - start < timeoutMs) {
      if (this.buffer.length !== lastLen) {
        lastLen = this.buffer.length;
        idleStart = Date.now();
      }
      if (Date.now() - idleStart >= idleMs) return true;
      await this.sleep(50);
    }
    return false;
  }

  captureArtifact(name) {
    const screen = this.readScreen();
    const filePath = path.join(this.artifactDir, `${name}.txt`);
    fs.writeFileSync(filePath, screen);
    return filePath;
  }

  async close() {
    if (this.term) {
      this.term.write('\x03'); // Ctrl-C
      await this.sleep(200);
      this.term.write('q');    // quit key
      await this.sleep(200);
      this.term.kill();
      this.term = null;
    }
  }

  sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
  }
}
