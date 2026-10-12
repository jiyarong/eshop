import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { code as normalize } from './normalize.mjs';
import { code as sensitivity } from './sensitivity.mjs';
import { code as validateAttributes } from './validate_attributes.mjs';
import { code as validateText } from './validate_text.mjs';
import { code as report } from './report.mjs';

const sources = JSON.parse(readFileSync(new URL('./fixtures/JJ005-6.json', import.meta.url)));
const search = { success: true, rows: [], pagination: { has_more: false } };
const context = () => normalize({ sources: structuredClone(sources), search_details: search });
const attributes = () => ({ sku_code: 'JJ005-6', listings: [{ sku_product_id: 253, assessment: 'KEEP', problems: [], actions: [], limitations: [] }] });
const moduleKeep = { quality: 'pass', action: 'KEEP', reason: '符合及格线', recommended_ru: null, recommended_zh: null };
const text = () => ({ sku_code: 'JJ005-6', listings: [{ sku_product_id: 253, summary: '维持现状', top_issues: ['KEEP'], problems: [], limitations: [],
  title: { ...moduleKeep }, description: { ...moduleKeep }, rich_content: { ...moduleKeep, quality: 'not_configured' },
  funnel_attribution: { listing_explains_anomaly: false, explanation: '暂无Listing归因依据' },
  seo: { traffic_quality: 'insufficient_data', verified_terms: [], explanation: '未获取词明细' } }] });
const runAttributes = async d => validateAttributes({ diagnosis: d, context: await context() });
const runText = async d => { const c = await context(); return validateText({ diagnosis: d, context: c, policy: await sensitivity({ context: c, config: sources.config }) }); };

test('real source parses PostgreSQL JSON strings and independent Ozon Listing', async () => {
  const c = await context();
  assert.equal(c.listings.length, 1);
  assert.equal(c.listings[0].store_name, 'NEVASTAL');
  assert.ok(c.listings[0].description.includes('Полки'));
  assert.equal(c.listings[0].rich_content_configured, false);
  assert.equal(c.listings[0].attributes.find(a => a.id === 6656).max_count, 2);
  assert.equal(c.listings[0].attributes.find(a => a.id === 6712).max_count, null);
});
test('wrong SKU/date/time zone and paginated incomplete data stop diagnosis', async () => {
  for (const mutate of [s => s.funnel.meta.sku_code = 'OTHER', s => s.search.meta.period.time_zone = 'UTC', s => s.inventory.meta.period.as_of = '2026-10-09', s => s.catalog.pagination.has_more = true]) {
    const s = structuredClone(sources); mutate(s);
    await assert.rejects(normalize({ sources: s, search_details: search }));
  }
});
test('missing critical Listing and catalog source fails before LLM', async () => {
  for (const mutate of [s => s.listing.rows[0].source_found = false, s => s.listing.rows[0].attributes_synced = false, s => s.catalog.rows = []]) {
    const s = structuredClone(sources); mutate(s);
    await assert.rejects(normalize({ sources: s, search_details: search }));
  }
});
test('partial-week conversion does not trigger a Listing defect or higher sensitivity', async () => {
  const c = await context(), p = await sensitivity({ context: c, config: sources.config });
  assert.equal(p.listings[0].text_strategy, 'pass_then_keep');
  assert.equal(p.listings[0].funnel_anomaly, false);
  assert.equal(p.listings[0].latest_complete_period.period_key, 'P-1');
});
test('search rankings deduplicate by Listing/week/query without adding user counts', async () => {
  const source = JSON.parse(readFileSync(new URL('./fixtures/search-details.json', import.meta.url)));
  const c = await normalize({ sources: structuredClone(sources), search_details: source });
  assert.equal(c.listings[0].search_terms.length, 150);
  const term = c.listings[0].search_terms.find(t => t.source_rankings.length > 1);
  const raw = source.rows.find(t => t.query === term.query && t.period_from === term.period_from);
  assert.equal(term.unique_view_users, raw.unique_view_users);
});
test('S/A and NEW increase sensitivity; CLR retains KEEP policy', async () => {
  for (const [grade, stage, expected] of [['S', 'MAT', 'pass_then_high_value_only'], ['C', 'NEW', 'pass_then_high_value_only'], ['S', 'CLR', 'pass_then_keep']]) {
    const c = await context(); c.grade = grade; c.stage = stage;
    assert.equal((await sensitivity({ context: c, config: sources.config })).listings[0].text_strategy, expected);
  }
});
test('official dictionary accepts exact ID/value, rejects invented values and max_count overflow', async () => {
  const c = await context(), a = c.listings[0].attributes.find(a => a.id === 6656), d = attributes();
  d.listings[0].assessment = 'CHANGE';
  d.listings[0].problems = [{ id: 'A1', attribute_id: 6656, complex_id: 0, priority: 'P1', confidence: 'high', current_evidence: 'МДФ', fact_evidence: '钢框架和MDF板', impact: '结构化搜索', recommendation: '保留合法值' }];
  d.listings[0].actions = [{ problem_id: 'A1', attribute_id: 6656, complex_id: 0, suggested_values: a.current_values }];
  await runAttributes(d);
  const invented = structuredClone(d); invented.listings[0].actions[0].suggested_values[0].value = 'Invented option';
  await assert.rejects(runAttributes(invented), /official options/);
  const overflow = structuredClone(d); overflow.listings[0].actions[0].suggested_values = a.options.slice(0, 3);
  await assert.rejects(runAttributes(overflow), /max_count/);
});
test('exempt model fields and evidence from other Listing cannot produce issues', async () => {
  const d = attributes(); d.listings[0].assessment = 'insufficient_data';
  d.listings[0].problems = [{ id: 'A1', attribute_id: 9048, priority: 'P0', confidence: 'high', current_evidence: 'JJ00', fact_evidence: 'x', impact: 'x', recommendation: 'x' }];
  await assert.rejects(runAttributes(d), /exempt/);
  d.listings[0].problems[0].attribute_id = 6656; d.listings[0].problems[0].current_evidence = 'other store';
  await assert.rejects(runAttributes(d), /evidence/);
});
test('B/C passing text stays KEEP and cannot turn missing SEO terms into verified traffic', async () => {
  const d = text(); await runText(d);
  d.listings[0].seo.traffic_quality = 'no_verified_irrelevant';
  await assert.rejects(runText(d), /SEO evidence/);
  const rewrite = text();
  const l = (await context()).listings[0];
  rewrite.listings[0].problems = [{ id: 'T1', module: 'title', priority: 'P1', confidence: 'high', current_evidence: l.title.slice(0, 20), fact_evidence: 'x', impact: 'x', recommendation: 'x' }];
  Object.assign(rewrite.listings[0].title, { action: 'REWRITE', recommended_ru: 'Русский текст', recommended_zh: '中文' });
  await assert.rejects(runText(rewrite), /must KEEP/);
});
test('incomplete native AI output and unsupported funnel attribution fail', async () => {
  await assert.rejects(runAttributes(undefined), /coverage/);
  await assert.rejects(runAttributes({ sku_code: 'JJ005-6' }), /coverage/);
  await assert.rejects(runText(undefined), /coverage/);
  const d = text(); d.listings[0].funnel_attribution.listing_explains_anomaly = true;
  await assert.rejects(runText(d), /Unsupported funnel attribution/);
});
test('SEO terms accept text or evidence objects but must exactly exist in the source', async () => {
  const c = await context(), d = text();
  c.listings[0].search_terms = [{ query: 'гараж сборный' }];
  d.listings[0].seo = { traffic_quality: 'verified_irrelevant', verified_terms: [{ query: 'гараж сборный', evidence: '词级明细' }], explanation: '跨品类' };
  d.listings[0].problems = [{ id: 'S1', module: 'seo', priority: 'P1', confidence: 'high', current_evidence: 'гараж сборный', fact_evidence: '车库建筑与货架主体不同', impact: '意图不匹配', recommendation: '排查来源' }];
  const inputs = { diagnosis: d, context: c, policy: await sensitivity({ context: c, config: sources.config }) };
  assert.deepEqual((await validateText(inputs)).listings[0].seo.verified_terms, ['гараж сборный']);
  d.listings[0].seo.verified_terms = ['invented term'];
  await assert.rejects(validateText(inputs), /absent from source/);
});
test('any P0 always overrides healthy model claims; missing required text cannot produce healthy', async () => {
  const c = await context(), p = await sensitivity({ context: c, config: sources.config }), a = attributes(), t = text();
  a.listings[0].problems = [{ priority: 'P0', defect_type: '内部冲突', current_evidence: '6', fact_evidence: '4', impact: '冲突', recommendation: '核实' }];
  const inputs = { context: c, policy: p, attributes: a, text: t, config: sources.config };
  assert.equal((await report(inputs)).metrics.status, 'has_error');
  a.listings[0].problems = []; t.listings[0].description.quality = 'insufficient_data';
  assert.equal((await report(inputs)).metrics.status, null);
  assert.equal((await report(inputs)).metrics.audit_status, 'insufficient_data');
});
