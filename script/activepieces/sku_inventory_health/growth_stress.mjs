export const code = async ({ data: d, velocity: v, config: c }) => {
  const applicable = ['S', 'A'].includes(d.grade) && ['NEW', 'GRW'].includes(d.stage);
  if (!applicable) return { applicable: false, alerts: [] };
  const speed = v.v_effective;
  const total_cover_days = d.book_stock !== null && d.incoming_quantity !== null && speed > 0 ? (d.book_stock + d.incoming_quantity) / (1.3 * speed) : null;
  return { applicable, scenario: 'daily_sales_plus_30_pct', total_cover_days,
    shortage_risk: total_cover_days === null ? null : total_cover_days < c.lead_time_days,
    alerts: total_cover_days !== null && total_cover_days < c.lead_time_days ? [{ type: '销量增长压力测试', level: 'yellow', message: `销量增长30%时覆盖${total_cover_days.toFixed(1)}天，低于${c.lead_time_days}天。`, advice: '将增长情景单独纳入安全库存评估，保持基准指标独立。' }] : [] };
};
