export const code = async ({ data: d, velocity: v, events: e, supply: s, channels: ch }) => {
  if (e.suppress_overstock) return { suppressed: true, reasons: [e.low_stock_gate && 'near_stockout', e.receipt_gate && 'receipt_14d_protection'].filter(Boolean), alerts: [], recovery_advice: e.receipt_recovery_advice };
  const alerts = [];
  if (s.total_cover_days > 180) alerts.push({ type: '库存积压', level: 'red', message: `全链库存覆盖${s.total_cover_days.toFixed(1)}天，超过180天。`, advice: '压缩后续排产并评估促销去库存。' });
  if (v.v_effective === 0 && d.book_stock > 0) alerts.push({ type: '库存积压', level: 'yellow', message: '有在库库存但有效日销为0。', advice: '排查链接、价格和投放，并核实库存去化方案。' });
  for (const channel of ch.channels) {
    if (channel.fbo_stock > 0 && channel.days_of_stock > 90) alerts.push({ type: '库存积压', level: 'yellow', message: `${channel.platform.toUpperCase()}官方仓周转超过90天。`, advice: '核实平台超期仓储费风险并优化官方仓存量。', evidence: channel });
    const listing = d.listings.find(row => row.store_id === channel.store_id && row.platform === channel.platform);
    const history = listing?.rows_per_week || [];
    const dormant = history.length >= 3 && history.every(row => row.values.orders === 0);
    if (channel.fbo_stock === 0 && channel.fbs_stock > 0 && dormant) alerts.push({ type: '动销异常 · 渠道 Listing 休眠', level: 'yellow', message: `${channel.platform.toUpperCase()}仅FBS挂载库存，多个周期没有订单。`, advice: '排查链接屏蔽、定价和广告；白俄FBS库存不产生平台仓储费。', evidence: channel });
  }
  return { suppressed: false, reasons: [], alerts };
};
