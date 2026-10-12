export const code = async ({ data: d, velocity: v, events: e }) => {
  const total = d.book_stock !== null && d.incoming_quantity !== null ? d.book_stock + d.incoming_quantity : null;
  const deadline = e.clr_entry_date ? new Date(Date.parse(e.clr_entry_date) + 90 * 86400000).toISOString().slice(0, 10) : null;
  const days_left = deadline ? (Date.parse(deadline) - Date.parse(d.as_of)) / 86400000 : null;
  const days_to_clear = total !== null && v.v_effective > 0 ? total / v.v_effective : null;
  const overdue_days = days_to_clear !== null && days_left !== null ? days_to_clear - days_left : null;
  const alerts = [];
  const stalled = total > 0 && v.v_effective === 0;
  if (total !== 0 && (stalled || overdue_days > 0)) alerts.push({ type: '清库超期', level: stalled || overdue_days > 30 ? 'red' : 'yellow',
    message: stalled ? '清库库存仍有剩余，但销售停滞。' : `按当前动销预计超过清库期限${overdue_days.toFixed(1)}天。`,
    advice: '调整清仓价格与渠道配置，按固定90天清仓周期复核进度。' });
  return { clearance_total: total, clr_entry_date: e.clr_entry_date, clr_entry_estimated: e.clr_entry_estimated,
    latest_clearance_date: deadline, days_left, days_to_clear, overdue_days, stalled, completed: total === 0, alerts,
    missing: [total === null && 'clearance_total', !deadline && 'clr_entry_date', v.v_effective === null && 'v_effective'].filter(Boolean) };
};
