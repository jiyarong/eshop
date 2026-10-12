export const code = async ({ data: d }) => {
  const age = date => (Date.parse(d.as_of) - Date.parse(String(date).slice(0, 10))) / 86400000;
  const incoming_batches = d.events.filter(e => e.event_type === 'purchase_ordered' && e.content?.status === 'ordered' && e.content.expected_arrival_on > d.as_of && e.occurred_on <= d.as_of)
    .sort((a, b) => a.content.expected_arrival_on.localeCompare(b.content.expected_arrival_on))
    .map(e => ({ event_id: e.id, batch_code: e.content.batch_code, quantity: e.content.purchased_quantity ?? null, expected_arrival_on: e.content.expected_arrival_on }));
  const next_arrival = incoming_batches[0] || null;
  const recent_receipt = d.events.some(e => e.event_type === 'purchase_received' && age(e.occurred_on) >= 0 && age(e.occurred_on) <= 14);
  const p0 = d.funnel_periods.find(p => p.period_key === 'P0')?.values.sku_ending_inventory;
  const p1 = d.funnel_periods.find(p => p.period_key === 'P-1')?.values.sku_ending_inventory;
  const inventory_jump = p0 != null && p1 != null && p0 - p1 > 100;
  const low_stock_gate = (d.days_in_stock !== null && d.days_in_stock < 7) || (d.book_stock !== null && d.book_stock < 10);
  const receipt_gate = recent_receipt || inventory_jump;
  const clr_event = d.events.filter(e => e.event_type === 'marketing_state_changed' && String(e.content?.to_stage).toUpperCase() === 'CLR' && e.occurred_on <= d.as_of)
    .sort((a, b) => b.occurred_on.localeCompare(a.occurred_on))[0];
  return { incoming_batches, next_arrival,
    days_until_next_arrival: next_arrival ? -age(next_arrival.expected_arrival_on) : null,
    low_stock_gate, receipt_gate, suppress_overstock: low_stock_gate || receipt_gate,
    clr_entry_date: clr_event?.occurred_on || (d.stage === 'CLR' ? String(d.first_sale_at || d.data_started_on || '').slice(0, 10) || null : null),
    clr_entry_estimated: d.stage === 'CLR' && !clr_event,
    receipt_recovery_advice: receipt_gate && ['S', 'A'].includes(d.grade) && d.stage !== 'CLR' ?
      '新货入库后检查并恢复WB/Ozon站内广告、正常活动销售价，并安排现货向官方仓送货分仓。' : null };
};
