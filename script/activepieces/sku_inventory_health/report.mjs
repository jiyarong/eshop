export const code = async (inputs) => {
  const { data: d, velocity: v, finance: f, events: e } = inputs;
  const objects = [inputs.supply, inputs.replenishment, inputs.channels, inputs.overstock, inputs.stress, inputs.clearance, inputs.clearance_finance].filter(x => x && typeof x === 'object');
  const missing = [...new Set([...d.missing, ...f.missing, ...objects.flatMap(x => x.missing || []), ...(v.v_effective === null ? ['v_effective'] : [])])];
  const rank = { red: 2, yellow: 1, green: 0 };
  const alerts = objects.flatMap(x => x.alerts || []).sort((a, b) => (b.type === '补货预警') - (a.type === '补货预警') || rank[b.level] - rank[a.level]);
  const supply = inputs.supply || {};
  const clr = inputs.clearance || {};
  const replenishment = inputs.replenishment || {};
  const unknown_stage = !['NEW', 'GRW', 'MAT', 'CLR'].includes(d.stage);
  const risk_level = alerts.some(x => x.level === 'red') ? 'red' : alerts.length || missing.length ? 'yellow' : 'green';
  const round = value => typeof value === 'number' && Number.isFinite(value) ? Math.round(value * 10000) / 10000 : value ?? null;
  const metrics = Object.fromEntries(Object.entries({ book_stock: d.book_stock, incoming_quantity: d.incoming_quantity,
    v_effective: v.v_effective, days_in_stock: d.days_in_stock, total_cover_days: d.stage === 'CLR' ? clr.days_to_clear : supply.total_cover_days,
    next_arrival_date: e.next_arrival?.expected_arrival_on, next_arrival_quantity: e.next_arrival?.quantity,
    stockout_days_immediate: supply.stockout_days_immediate, missed_profit_cny: supply.missed_profit,
    lead_time_gap: supply.lead_time_gap, buffer_days: supply.buffer_days,
    suggested_replenishment_quantity: d.stage === 'CLR' ? 0 : replenishment.suggested_quantity,
    replenishment_target_days: replenishment.target_days, avg_profit_per_unit_cny: f.avg_profit_per_unit,
    annualized_return_pct: f.annualized_return_pct, clearance_total: clr.clearance_total,
    latest_clearance_date: clr.latest_clearance_date, days_to_clear: clr.days_to_clear, overdue_days: clr.overdue_days }).map(([k, value]) => [k, round(value)]));
  const labels = { book_stock: '当前库存', incoming_quantity: '在途库存', v_effective: '基准日销', days_in_stock: '在库覆盖天数', total_cover_days: '全链覆盖天数', next_arrival_date: '最近预计到货日', suggested_replenishment_quantity: '建议补货量' };
  const markdown = [`# ${d.sku_code} 库存诊断`, `Grade / Stage：${d.grade || '缺失'} / ${d.stage || '缺失'}`, `基准日期：${d.as_of}（${d.time_zone}）`,
    `综合风险：${{ red: '红', yellow: '黄', green: '绿' }[risk_level]}；诊断标签：${[...new Set(alerts.map(x => x.type))].join('、') || (missing.length ? '数据不足' : '未命中风险')}`,
    '', '| 指标 | 数值 |', '| --- | --- |', ...Object.entries(labels).map(([key, label]) => `| ${label} | ${metrics[key] ?? '数据缺失'} |`), '',
    ...alerts.flatMap(x => [`## ${x.type}`, x.message, x.advice,
      x.type === '到货前断货' && metrics.missed_profit_cny !== null ? `预计错失利润：${metrics.missed_profit_cny}元；按三周平滑单件净利测算。` : '',
      x.type === '渠道失衡' && x.evidence?.distribution_gap > 0 ? `官方仓分布缺口：${x.evidence.distribution_gap}件；优先集群：${x.evidence.top_clusters.map(c => `${c.cluster_name} ${c.suggested_quantity}件`).join('、')}。` : '', '']),
    replenishment.reason || '', replenishment.warning || '',
    supply.gap_explanation || '', e.clr_entry_estimated ? '清仓起点为估算值。' : '',
    missing.length ? `数据缺口：${missing.join('、')}。` : '', ...v.warnings].filter(x => x !== null).join('\n');
  return { sku_code: d.sku_code, as_of: d.as_of, time_zone: d.time_zone, grade: d.grade, stage: d.stage,
    status: missing.length || unknown_stage ? 'insufficient_data' : 'completed', risk_level, tags: [...new Set(alerts.map(x => x.type))],
    metrics, alerts, missing, markdown, evidence: { selection: d.selection, source_periods: d.source_periods,
      inventory_data_through: d.inventory_data_through, velocity: v, finance: f, arrivals: e, supply, replenishment,
      channel_health: inputs.channels || null, overstock: inputs.overstock || null, stress: inputs.stress || null,
      clearance: inputs.clearance || null, clearance_finance: inputs.clearance_finance || null } };
};
