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

  // S7: Audit trail page shows event log with severity badges
  test('S7: audit trail page renders event log', async ({ page }) => {
    await page.goto('/audit-trail');
    await expect(page.locator('h1')).toContainText('Audit Trail');
    const table = page.locator('#audit-table');
    await expect(table).toBeVisible();
    const rows = table.locator('tbody tr');
    await expect(rows).toHaveCount(5);
    // Verify severity badges render
    const badges = table.locator('.badge');
    expect(await badges.count()).toBeGreaterThanOrEqual(5);
    // Verify hash column shows truncated hash
    const hashCell = rows.first().locator('code');
    await expect(hashCell).toBeVisible();
    const hashText = await hashCell.textContent();
    expect(hashText!.length).toBe(8);
  });

  // S8: Analytics page shows summary cards, duration histogram, and efficiency table
  test('S8: analytics page renders metrics dashboard', async ({ page }) => {
    await page.goto('/analytics');
    await expect(page.locator('h1')).toContainText('Session Analytics');
    // Summary cards
    const cards = page.locator('#summary-cards .metric-card');
    await expect(cards).toHaveCount(5);
    // Verify specific values
    await expect(cards.first().locator('.metric-value')).toContainText('3');
    // Duration distribution table
    const durationTable = page.locator('#duration-table');
    await expect(durationTable).toBeVisible();
    const durationRows = durationTable.locator('tbody tr');
    await expect(durationRows).toHaveCount(5);
    // Efficiency table
    const effTable = page.locator('#efficiency-table');
    await expect(effTable).toBeVisible();
    const effRows = effTable.locator('tbody tr');
    await expect(effRows).toHaveCount(3);
  });

  // S7-API + S8-API: Audit trail and analytics JSON APIs
  test('S7+S8 API: audit-trail and analytics return valid JSON', async ({ request }) => {
    // Audit trail API
    const audit = await request.get('/api/audit-trail');
    expect(audit.ok()).toBeTruthy();
    const auditData = await audit.json();
    expect(auditData).toHaveLength(5);
    expect(auditData[0].category).toBe('session-lifecycle');
    expect(auditData[0].severity).toBe('info');

    // Analytics API
    const analytics = await request.get('/api/analytics');
    expect(analytics.ok()).toBeTruthy();
    const analyticsData = await analytics.json();
    expect(analyticsData.summary.total_sessions).toBe(3);
    expect(analyticsData.duration_buckets).toHaveLength(5);
    expect(analyticsData.efficiency).toHaveLength(3);
  });
});
