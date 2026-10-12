export const code = async ({ finance: f, clearance: c }) => {
  const total_goods_cost = c.clearance_total !== null && f.unit_goods_cost !== null ? c.clearance_total * f.unit_goods_cost : null;
  const raw_projected_profit = c.clearance_total !== null && f.avg_profit_per_unit !== null ? c.clearance_total * f.avg_profit_per_unit : null;
  const loss_ratio = f.avg_profit_per_unit < 0 && f.unit_goods_cost > 0 ? Math.abs(f.avg_profit_per_unit) / f.unit_goods_cost : null;
  const ad_distortion = f.avg_profit_per_unit < 0 && ((f.ad_ratio_pct !== null && f.ad_ratio_pct > 25) || (f.unit_goods_cost !== null && Math.abs(f.avg_profit_per_unit) > f.unit_goods_cost));
  const alerts = [];
  if (c.clearance_total > 0 && ad_distortion) alerts.push({ type: '广告空转失血', level: 'red',
    message: '广告费占比或单件亏损命中失真保护；需核查低动销下广告费用分摊，不能据此直接认定商品刚性亏损。',
    advice: '暂停或大幅调低付费广告，将预算转为清仓折让；如白俄总仓有可用现货，可小批量20～30件送往官方仓。' });
  else if (c.clearance_total > 0 && f.avg_profit_per_unit < 0) alerts.push({ type: '清库亏损', level: loss_ratio > 0.3 ? 'red' : 'yellow',
    message: loss_ratio !== null ? `按平滑利润测算，清库亏损约占货值${(loss_ratio * 100).toFixed(1)}%。` : '当前平滑单件利润为负，货值成本不足以核算亏损率。', advice: '核实清仓价格底线与可接受亏损预算。' });
  return { total_goods_cost, raw_projected_profit, loss_ratio, ad_distortion, alerts,
    limitation: ad_distortion ? '广告失真时账面预计损益仅作原始证据，不作为真实清库亏损预测。' : null };
};
