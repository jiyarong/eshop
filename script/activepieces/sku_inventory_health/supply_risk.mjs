export const code = async ({ data: d, velocity: v, finance: f, events: e, config: c }) => {
  const speed = v.v_effective;
  const canCalculate = d.book_stock !== null && d.incoming_quantity !== null && speed !== null && speed > 0;
  const useContext = !v.calibrated && d.context_total_cover_days !== null;
  const total_cover_days = useContext ? d.context_total_cover_days : canCalculate ? (d.book_stock + d.incoming_quantity) / speed : null;
  const stockout_days_immediate = e.days_until_next_arrival !== null && d.days_in_stock !== null && speed > 0 ? Math.max(0, e.days_until_next_arrival - d.days_in_stock) : null;
  const stockout_date = d.days_in_stock !== null ? new Date(Date.parse(d.as_of) + Math.floor(d.days_in_stock) * 86400000).toISOString().slice(0, 10) : null;
  const missed_profit = stockout_days_immediate !== null && f.avg_profit_per_unit !== null && speed !== null ? stockout_days_immediate * speed * Math.max(0, f.avg_profit_per_unit) : null;
  const weekly_loss = f.avg_profit_per_unit !== null && speed !== null ? speed * Math.max(0, f.avg_profit_per_unit) * 7 : null;
  const alerts = [];
  if (total_cover_days !== null && total_cover_days < c.lead_time_days) alerts.push({ type: '补货预警', level: 'red',
    message: `全链覆盖${total_cover_days.toFixed(1)}天，距${c.lead_time_days}天供应周期缺${(c.lead_time_days - total_cover_days).toFixed(1)}天。`,
    advice: '立即启动采购排产，并核实到货节奏。', evidence: { total_cover_days, lead_time_days: c.lead_time_days } });
  if (stockout_days_immediate > 0) alerts.push({ type: '到货前断货', level: weekly_loss >= 2000 ? 'red' : 'yellow',
    message: `预计${stockout_date}库存耗尽，下一批${e.next_arrival.expected_arrival_on}到达，间隔${stockout_days_immediate.toFixed(1)}天。`,
    advice: f.avg_profit_per_unit < 0 ? '当前单件亏损，断货在财务上减少亏损；补货前核实盈利能力。' : '协调现有在途到货和可用渠道调拨，降低近期断档。',
    evidence: { stockout_days_immediate, missed_profit, weekly_loss, profit_impact: f.avg_profit_per_unit < 0 ? 'loss_reduction' : f.avg_profit_per_unit === null ? 'unknown' : 'lost_profit' } });
  return { total_cover_days, cover_source: useContext ? 'context.turnover_days_with_procurement' : canCalculate ? 'calibrated_or_missing_metric_formula' : 'missing',
    stockout_date, stockout_days_immediate, missed_profit, weekly_loss,
    lead_time_gap: total_cover_days !== null ? Math.max(0, c.lead_time_days - total_cover_days) : null,
    buffer_days: total_cover_days !== null ? Math.max(0, total_cover_days - c.lead_time_days) : null,
    gap_explanation: total_cover_days !== null && total_cover_days < c.lead_time_days && stockout_days_immediate > 0 ?
      '90天总供给缺口与首轮到货前断档重叠，后续在途耗尽还可能形成次轮断档；两者不可直接相加。' : null,
    alerts, missing: [total_cover_days === null && 'total_cover_days', stockout_days_immediate === null && d.incoming_quantity > 0 && 'immediate_gap_arrival_or_cover'].filter(Boolean) };
};
