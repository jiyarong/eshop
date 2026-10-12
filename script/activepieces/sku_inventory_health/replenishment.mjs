export const code = async ({ data: d, velocity: v, finance: f, supply: s, config: c, events: e, stage_policy: p }) => {
  if (s.total_cover_days === null) return { suggested_quantity: null, target_days: null, status: 'insufficient_data', reason: '缺少全链覆盖或有效日销，暂不能确定补货量。' };
  if (s.total_cover_days >= c.lead_time_days) return { suggested_quantity: 0, target_days: 0, status: 'covered', reason: `当前覆盖完整供应周期，可在${s.buffer_days.toFixed(1)}天缓冲内启动下一批排产。` };
  const priority = ['S', 'A'].includes(d.grade) || f.annualized_return_pct > c.high_return_pct;
  const target_days = priority ? p.priority_target_days : p.standard_target_days;
  const raw_quantity = target_days * v.v_effective;
  const past = d.events.filter(event => event.event_type === 'purchase_ordered' && event.occurred_on <= d.as_of && event.content?.purchased_quantity != null && Number(event.content.purchased_quantity) > 0)
    .sort((a, b) => b.occurred_on.localeCompare(a.occurred_on));
  const standard_lot = past.length ? Number(past[0].content.purchased_quantity) : null;
  const near_lot = standard_lot ? Math.max(1, Math.round(raw_quantity / standard_lot)) * standard_lot : null;
  const round_to_lot = near_lot !== null && Math.abs(near_lot - raw_quantity) / raw_quantity <= c.lot_rounding_tolerance && !(d.stage === 'NEW' && near_lot > raw_quantity);
  const suggested_quantity = round_to_lot ? Math.ceil(near_lot) : Math.ceil(raw_quantity);
  const finance_review = f.avg_profit_per_unit < 0 || (f.annualized_return_pct !== null && f.annualized_return_pct < c.low_return_pct);
  return { suggested_quantity, raw_quantity, target_days, standard_lot, rounded_to_lot: round_to_lot,
    status: finance_review ? 'review_profit_before_order' : 'replenish', finance_review,
    reason: `按新批次到货后${target_days}天动销备货：${target_days} × ${v.v_effective.toFixed(4)} = ${raw_quantity.toFixed(1)}件，建议${suggested_quantity}件。交期内损失销量不再重复计入；之后每月按约${c.normal_monthly_days}天动销复核采购。`,
    warning: finance_review ? '当前利润或年化回报不足，确认补货收益后再下单。' : f.avg_profit_per_unit === null || f.annualized_return_pct === null ? '利润或年化回报缺失，采购前补充核实。' : null,
    next_arrival: e.next_arrival };
};
