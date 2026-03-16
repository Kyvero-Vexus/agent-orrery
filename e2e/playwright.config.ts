import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright E2E config for Agent Orrery Web Dashboard (Epic 4).
 *
 * Deterministic command path:
 *   cd e2e && npx playwright test              — run all S1-S6 scenarios
 *   cd e2e && npx playwright test --trace on   — with full traces
 *   cd e2e && npx playwright show-report       — view HTML report
 *   cd e2e && ./run-e2e.sh                     — deterministic wrapper
 *
 * Expects the CL web server on BASE_URL (default http://localhost:7890).
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: false,          // sequential for deterministic replay
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,                    // single worker for determinism
  reporter: [
    ['html', { open: 'never', outputFolder: '../test-results/e2e-report' }],
    ['list'],
  ],

  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:7890',
    trace: 'on',                 // always capture traces
    screenshot: 'on',            // screenshot after every test
    video: 'retain-on-failure',
    actionTimeout: 10_000,
    navigationTimeout: 15_000,
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  /* CL web server started separately; uncomment to auto-launch:
  webServer: {
    command: 'sbcl --load start-server.lisp',
    url: 'http://localhost:7890',
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
  */

  outputDir: '../test-results/e2e-artifacts',
});
