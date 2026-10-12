import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { code as normalize } from './normalize.mjs';
import { code as calibrate } from './calibrate_velocity.mjs';
import { code as finance } from './smooth_finance.mjs';
import { code as events } from './events_and_gates.mjs';
import { code as supply } from './supply_risk.mjs';
import { code as replenish } from './replenishment.mjs';
import { code as channels } from './channel_health.mjs';
import { code as overstock } from './overstock.mjs';
import { code as stress } from './growth_stress.mjs';
import { code as clearance } from './clearance_schedule.mjs';
import { code as clearanceFinance } from './clearance_finance.mjs';
import { code as report } from './report.mjs';

const fixture = JSON.parse(fs.readFileSync(new URL('./fixtures/JJ005-6.json', import.meta.url), 'utf8'));
const fresh = () => structuredClone(fixture);
const bc = { shortage_days: 14, shortage_stock: 20 };
const stagePolicy = { standard_target_days: 45, priority_target_days: 60 };
const approx = (actual, expected) => assert.ok(Math.abs(actual - expected) < 0.001, `${actual} != ${expected}`);
async function run(input = fresh()) {
  const data = await normalize(input);
  const velocity = await calibrate({ data, policy: bc });
  const financial = await finance({ data });
  const eventData = await events({ data });
  const common = { data, velocity, finance: financial, events: eventData, config: input.config };
  const supplyData = await supply(common);
  const replenishment = await replenish({ ...common, supply: supplyData, stage_policy: stagePolicy });
  const channelData = await channels({ data });
  const overstockData = await overstock({ ...common, supply: supplyData, channels: channelData });
  return { ...common, supply: supplyData, replenishment, channels: channelData, overstock: overstockData };
}

test('live API sample produces independently checked inventory decision', async () => {
  const result = await run();
  const output = await report(result);
  assert.equal(output.status, 'completed');
  assert.equal(output.risk_level, 'red');
  assert.equal(output.tags[0], '补货预警');
  approx(output.metrics.total_cover_days, 237 / 6.2143);
  approx(output.metrics.stockout_days_immediate, 51 - 5.9540093011280435);
  approx(output.metrics.avg_profit_per_unit_cny, (479.23 + 1426.89 + 1678.57) / 64);
  assert.equal(output.metrics.suggested_replenishment_quantity, 400);
  assert.equal(result.overstock.suppressed, true);
  assert.equal(result.channels.channels[0].distribution_gap, 50);
});

test('missing inventory stays missing and cannot produce green or zero replenishment', async () => {
  const input = fresh();
  input.inventory.current.values.book_stock = null;
  input.inventory.current.values.incoming_quantity = null;
  const output = await report(await run(input));
  assert.equal(output.metrics.book_stock, null);
  assert.equal(output.metrics.incoming_quantity, null);
  assert.equal(output.metrics.suggested_replenishment_quantity, null);
  assert.equal(output.status, 'insufficient_data');
  assert.notEqual(output.risk_level, 'green');
});

test('available_metrics excludes unsupported metrics; invalid forecast falls back', async () => {
  const input = fresh();
  input.inventory.current.available_metrics = ['incoming_quantity', 'daily_sales_velocity', 'turnover_days'];
  input.inventory.current.strict_forecast.valid_days = 0;
  const data = await normalize(input);
  assert.equal(data.book_stock, null);
  assert.equal(data.strict_daily_sales, null);
  approx(data.regular_daily_sales, 4.022857142857143);
  approx(data.days_in_stock, 9.197443181818182);
});

test('different context dates or SKUs fail before a diagnosis', async () => {
  const input = fresh();
  input.profit.meta.period.as_of = '2026-10-09';
  await assert.rejects(normalize(input), /inconsistent context/);
  input.profit.meta.period.as_of = input.base.meta.period.as_of;
  input.profit.meta.sku_code = 'OTHER';
  await assert.rejects(normalize(input), /unexpected schema or SKU/);
});

test('uncalibrated context cover is used as supplied, without replacing it with division', async () => {
  const input = fresh();
  input.lifecycle.events = [];
  input.inventory.current.values.book_stock = 1000;
  input.inventory.current.values.strict_forecast_cover_days = 160;
  input.inventory.current.values.turnover_days_with_procurement = 123;
  const result = await run(input);
  assert.equal(result.velocity.calibrated, false);
  assert.equal(result.supply.total_cover_days, 123);
  assert.equal(result.replenishment.suggested_quantity, 0);
  assert.equal(result.supply.buffer_days, 33);
});

test('shortage calibration skips depleted weeks and uses the maximum stocked sample', async () => {
  const data = await normalize(fresh());
  data.weeks = [
    { week_start: '2026-09-07', missing: false, values: { book_stock: 80, daily_sales_velocity: 7 } },
    { week_start: '2026-09-14', missing: false, values: { book_stock: 70, daily_sales_velocity: 12 } },
    { week_start: '2026-09-21', missing: false, values: { book_stock: 60, daily_sales_velocity: 9 } },
    { week_start: '2026-09-28', missing: false, values: { book_stock: 5, daily_sales_velocity: 1 } },
    { week_start: '2026-10-05', missing: true, values: { book_stock: 90, daily_sales_velocity: 99 } }
  ];
  const value = await calibrate({ data, policy: bc });
  assert.equal(value.v_effective, 12);
  assert.equal(value.historical_samples.length, 3);
});

test('zero velocity causes no infinite arithmetic and detects stagnant inventory', async () => {
  const input = fresh();
  input.lifecycle.events = [];
  input.inventory.weeks = [];
  Object.assign(input.inventory.current.values, { strict_forecast_daily_sales: 0, daily_sales_velocity: 0, strict_forecast_cover_days: null, turnover_days: null, turnover_days_with_procurement: null });
  input.lifecycle.summary.values.inventory_cover_days = null;
  const result = await run(input);
  assert.equal(result.supply.total_cover_days, null);
  assert.equal(result.replenishment.suggested_quantity, null);
  assert.ok(result.overstock.alerts.some(alert => alert.type === '库存积压'));
  assert.ok(!JSON.stringify(await report(result)).includes('Infinity'));
});

test('profit missing from any required week never becomes zero or a false weighted profit', async () => {
  const input = fresh();
  input.profit.periods.find(row => row.period_key === 'P-1').values.after_tax = null;
  const financial = await finance({ data: await normalize(input) });
  assert.equal(financial.avg_profit_per_unit, null);
  assert.ok(financial.missing.includes('avg_profit_per_unit'));
});

test('NEW batches remain near thirty days even with high annualized returns', async () => {
  const result = await run();
  const value = await replenish({ ...result, data: { ...result.data, stage: 'NEW' }, stage_policy: { standard_target_days: 30, priority_target_days: 30 } });
  assert.equal(value.target_days, 30);
  assert.equal(value.suggested_quantity, 187);
});

test('recent purchase receipt mutes overstock and offers recovery advice for S/A', async () => {
  const data = await normalize(fresh());
  Object.assign(data, { grade: 'S', days_in_stock: 200, book_stock: 1000 });
  data.events.push({ event_type: 'purchase_received', occurred_on: data.as_of, content: { received_quantity: 300 } });
  const eventData = await events({ data });
  const value = await overstock({ data, events: eventData, velocity: { v_effective: 1 }, supply: { total_cover_days: 1200 }, channels: { channels: [] } });
  assert.equal(value.suppressed, true);
  assert.equal(value.alerts.length, 0);
  assert.match(value.recovery_advice, /广告/);
});

test('FBS is not counted across listings or charged official warehouse fees', async () => {
  const data = await normalize(fresh());
  for (const store of data.warehouses) Object.assign(store.summary, { available: 0, fbs_available: 100, days_of_stock: 300 });
  for (const listing of data.listings) for (const row of listing.rows_per_week) row.values.orders = 0;
  const channelData = await channels({ data });
  assert.equal(channelData.unallocated_stock, null);
  const value = await overstock({ data, channels: channelData, events: { suppress_overstock: false }, velocity: { v_effective: 2 }, supply: { total_cover_days: 100 } });
  assert.ok(value.alerts.every(alert => alert.type === '动销异常 · 渠道 Listing 休眠'));
});

test('growth stress runs only for S/A in NEW/GRW and keeps a separate scenario', async () => {
  const result = await run();
  assert.equal((await stress(result)).applicable, false);
  const value = await stress({ ...result, data: { ...result.data, grade: 'S' } });
  approx(value.total_cover_days, 237 / (6.2143 * 1.3));
  assert.equal(value.shortage_risk, true);
  assert.equal((await stress({ ...result, data: { ...result.data, grade: 'A', stage: 'MAT' } })).applicable, false);
});

test('CLR observes its event-based deadline, detects stagnation, and forbids replenishment', async () => {
  const result = await run();
  result.data.stage = 'CLR';
  const clr = await clearance({ ...result, velocity: { v_effective: 0 } });
  assert.equal(clr.latest_clearance_date, '2026-12-14');
  assert.equal(clr.stalled, true);
  assert.equal(clr.alerts[0].level, 'red');
  const output = await report({ data: result.data, velocity: { ...result.velocity, v_effective: 0 }, finance: result.finance, events: result.events, clearance: clr });
  assert.equal(output.metrics.suggested_replenishment_quantity, 0);
  assert.ok(!output.tags.includes('补货预警'));
});

test('CLR cost and ad-distortion gates keep raw loss separate from a confirmed loss', async () => {
  const value = await clearanceFinance({ finance: { avg_profit_per_unit: -20, unit_goods_cost: 50, ad_ratio_pct: 30 }, clearance: { clearance_total: 200 } });
  assert.equal(value.total_goods_cost, 10000);
  assert.equal(value.raw_projected_profit, -4000);
  assert.equal(value.ad_distortion, true);
  assert.equal(value.alerts[0].type, '广告空转失血');
  const normal = await clearanceFinance({ finance: { avg_profit_per_unit: -20, unit_goods_cost: 50, ad_ratio_pct: 10 }, clearance: { clearance_total: 200 } });
  assert.equal(normal.alerts[0].type, '清库亏损');
  assert.equal(normal.alerts[0].level, 'red');
});
