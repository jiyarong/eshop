export const code = async ({ data: d }) => {
  const periods = ['P0', 'P-1', 'P-2'].map(key => d.profit_periods.find(row => row.period_key === key));
  const complete = key => periods.every(row => row?.values?.[key] !== null && row?.values?.[key] !== undefined);
  const sum = key => periods.reduce((total, row) => total + row.values[key], 0);
  const sold = complete('net_sales') ? sum('net_sales') : null;
  const p0 = periods[0]?.values || {};
  const avg_profit_per_unit = sold !== null && sold > 0 && complete('after_tax') ? sum('after_tax') / sold :
    sold !== null && sold <= 0 ? (p0.average_profit_per_order ?? null) : null;
  const unit_goods_cost = sold !== null && sold > 0 && complete('goods_cost') ? sum('goods_cost') / sold : null;
  return { avg_profit_per_unit, unit_goods_cost, net_sales_3_weeks: sold,
    annualized_return_pct: p0.annualized_return_pct ?? null, ad_ratio_pct: p0.ad_ratio_pct ?? null,
    method: sold !== null && sold > 0 ? 'three_week_sales_weighted' : sold !== null ? 'p0_profit_fallback' : 'missing',
    periods: periods.filter(Boolean).map(row => ({ period_key: row.period_key, from: row.period_from, to: row.period_to })),
    missing: [avg_profit_per_unit === null && 'avg_profit_per_unit', unit_goods_cost === null && 'unit_goods_cost'].filter(Boolean) };
};
