export const code = async ({ data: d, policy }) => {
  const age = date => (Date.parse(d.as_of) - Date.parse(String(date).slice(0, 10))) / 86400000;
  const recent = (type, days) => d.events.some(e => e.event_type === type && age(e.occurred_on) >= 0 && age(e.occurred_on) <= days);
  const reasons = [];
  if (d.days_in_stock !== null && d.days_in_stock < policy.shortage_days) reasons.push('low_cover');
  if (d.book_stock !== null && d.book_stock < policy.shortage_stock) reasons.push('low_stock');
  if (recent('stock_recovered', 14)) reasons.push('stock_recovered_14d');
  if (recent('purchase_received', 7)) reasons.push('purchase_received_7d');
  const calibrated = reasons.length > 0;
  const samples = calibrated ? d.weeks.filter(w => !w.missing && w.values.book_stock !== null && w.values.book_stock >= policy.shortage_stock && w.values.daily_sales_velocity !== null && w.values.daily_sales_velocity >= 0)
    .sort((a, b) => b.week_start.localeCompare(a.week_start)).slice(0, 3) : [];
  const before = samples.length ? Math.max(...samples.map(w => w.values.daily_sales_velocity)) : null;
  const candidates = [before, d.strict_daily_sales, d.daily_sales_velocity].filter(v => v !== null);
  const v_effective = calibrated ? (candidates.length ? Math.max(...candidates) : null) : d.regular_daily_sales;
  return { calibrated, reasons, v_effective, daily_sales_before_shortage: before,
    historical_samples: samples.map(w => ({ week_start: w.week_start, book_stock: w.values.book_stock, daily_sales_velocity: w.values.daily_sales_velocity, is_week_end: w.is_week_end })),
    warnings: calibrated && samples.length < 3 ? ['断货校准可用历史样本不足3周，使用实际可用样本。'] : [] };
};
