import { test, expect } from '@playwright/test';

test.describe('Agent Orrery Web Dashboard E2E', () => {
  // S1: Dashboard loads, shows session count
  test('S1: dashboard loads and shows session count', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('h1')).toContainText('Agent Orrery Dashboard');
    const sessionCount = page.locator('#session-count');
    await expect(sessionCount).toBeVisible();
    const count = await sessionCount.textContent();
    expect(parseInt(count!)).toBeGreaterThan(0);
  });

  // S2: Navigate to sessions, verify table renders
  test('S2: sessions page renders table', async ({ page }) => {
    await page.goto('/sessions');
    await expect(page.locator('h1')).toContainText('Sessions');
    const table = page.locator('#sessions-table');
    await expect(table).toBeVisible();
    const rows = table.locator('tbody tr');
    await expect(rows).toHaveCount(3);
  });

  // S3: Session drill-down shows detail
  test('S3: session detail shows record', async ({ page }) => {
    await page.goto('/sessions/sess-001');
    await expect(page.locator('#session-detail')).toBeVisible();
    await expect(page.locator('#agent')).toContainText('gensym');
    await expect(page.locator('#model')).toContainText('claude-opus-4');
    await expect(page.locator('#status')).toContainText('ACTIVE');
  });

  // S4: Cron page shows job list
  test('S4: cron page renders job table', async ({ page }) => {
    await page.goto('/cron');
    await expect(page.locator('h1')).toContainText('Cron Jobs');
    const table = page.locator('#cron-table');
    await expect(table).toBeVisible();
    const rows = table.locator('tbody tr');
    await expect(rows).toHaveCount(3);
  });

  // S5: Alerts page renders
  test('S5: alerts page renders alert table', async ({ page }) => {
    await page.goto('/alerts');
    await expect(page.locator('h1')).toContainText('Alerts');
    const table = page.locator('#alerts-table');
    await expect(table).toBeVisible();
    const rows = table.locator('tbody tr');
    await expect(rows).toHaveCount(2);
  });

  // S6: API endpoints return valid JSON
  test('S6: API endpoints return valid JSON', async ({ request }) => {
    // Dashboard API
    const dashboard = await request.get('/api/dashboard');
    expect(dashboard.ok()).toBeTruthy();
    const dashData = await dashboard.json();
    expect(dashData.session_count).toBe(3);
    expect(dashData.active_count).toBe(1);

    // Sessions API
    const sessions = await request.get('/api/sessions');
    expect(sessions.ok()).toBeTruthy();
    const sessData = await sessions.json();
    expect(sessData).toHaveLength(3);
    expect(sessData[0].id).toBe('sess-001');

    // Health API
    const health = await request.get('/api/health');
    expect(health.ok()).toBeTruthy();
    const healthData = await health.json();
    expect(healthData).toHaveLength(3);
  });
});
