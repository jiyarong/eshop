export const code = async (inputs) => {
  const { config, base, inventory, lifecycle, profit, funnel, warehouse } = inputs;
  const sources = { base, inventory, lifecycle, profit, funnel, warehouse };
  for (const [name, source] of Object.entries(sources)) {
    if (source?.meta?.schema_version !== 3 || source.meta.sku_code !== config.sku_code)
      throw new Error(`${name}: unexpected schema or SKU`);
    if (source.meta.period?.as_of !== base.meta.period.as_of || source.meta.period?.time_zone !== base.meta.period.time_zone)
      throw new Error(`${name}: inconsistent context date or time zone`);
  }
  const as_of = base.meta.period.as_of;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(as_of)) throw new Error('Context as_of is required');
  const number = v => v === null || v === undefined || v === '' || typeof v === 'boolean' || !Number.isFinite(Number(v)) ? null : Number(v);
  const metric = (node, key) => Array.isArray(node?.available_metrics) && !node.available_metrics.includes(key) ? null : number(node?.values?.[key]);
  const rows = list => (Array.isArray(list) ? list : []).map(row => ({ ...row,
    values: Object.fromEntries(Object.keys(row.values || {}).map(key => [key, metric(row, key)])) }));
  const current = inventory.current;
  const summary = lifecycle.summary;
  const funnel_periods = rows(funnel.periods);
  const p0 = funnel_periods.find(row => row.period_key === 'P0');
  const pick = (...items) => items.find(item => item.value !== null && item.value !== undefined && item.value !== '') || { value: null, source: null };
  const selection = {
    book_stock: pick({ value: metric(current, 'book_stock'), source: 'inventory.current.values.book_stock' },
      { value: metric(p0, 'sku_ending_inventory'), source: 'sales_funnel.P0.values.sku_ending_inventory' }),
    incoming_quantity: { value: metric(current, 'incoming_quantity'), source: 'inventory.current.values.incoming_quantity' },
    days_in_stock: pick(...['strict_forecast_cover_days', 'turnover_days'].map(key => ({ value: metric(current, key), source: `inventory.current.values.${key}` })),
      { value: metric(summary, 'inventory_cover_days'), source: 'lifecycle.summary.values.inventory_cover_days' }),
    regular_daily_sales: pick({ value: number(current?.strict_forecast?.valid_days) === 0 ? null : metric(current, 'strict_forecast_daily_sales'), source: 'inventory.current.values.strict_forecast_daily_sales' },
      { value: metric(current, 'daily_sales_velocity'), source: 'inventory.current.values.daily_sales_velocity' },
      { value: metric(summary, 'daily_sales_velocity'), source: 'lifecycle.summary.values.daily_sales_velocity' })
  };
  const missing = Object.entries(selection).filter(([, item]) => item.value === null).map(([key]) => key);
  if (!Array.isArray(lifecycle.events)) missing.push('lifecycle_events');
  if (!Array.isArray(inventory.weeks)) missing.push('inventory_history');
  const grade = (summary?.values?.current_grade || base.base?.current_grade || '').toUpperCase() || null;
  const stage = (summary?.values?.current_stage || base.base?.current_stage || '').toUpperCase() || null;
  if (!grade) missing.push('grade');
  if (!['NEW', 'GRW', 'MAT', 'CLR'].includes(stage)) missing.push('stage');
  const values = Object.fromEntries(Object.entries(selection).map(([key, item]) => [key, item.value]));
  for (const [key, value] of Object.entries(values)) if (value !== null && value < 0) throw new Error(`${key}: negative inventory or velocity`);
  const profit_periods = rows(profit.periods);
  for (const row of profit_periods) {
    const span = (Date.parse(row.period_to) - Date.parse(row.period_from)) / 86400000;
    if (span !== 6) throw new Error('Profit periods must be independent seven-day weeks');
  }
  return { sku_code: config.sku_code, as_of, time_zone: base.meta.period.time_zone, grade, stage, ...values,
    strict_daily_sales: number(current?.strict_forecast?.valid_days) === 0 ? null : metric(current, 'strict_forecast_daily_sales'),
    daily_sales_velocity: metric(current, 'daily_sales_velocity') ?? metric(summary, 'daily_sales_velocity'),
    context_total_cover_days: metric(current, 'turnover_days_with_procurement'),
    forecast_valid_days: number(current?.strict_forecast?.valid_days), selection, missing,
    weeks: rows(inventory.weeks), events: Array.isArray(lifecycle.events) ? lifecycle.events : [],
    first_sale_at: summary?.values?.first_sale_at || null, data_started_on: lifecycle.data_started_on || null,
    profit_periods, funnel_periods,
    listings: (Array.isArray(funnel.listings) ? funnel.listings : []).map(listing => ({ ...listing, rows_per_week: rows(listing.rows_per_week) })),
    warehouses: Array.isArray(warehouse.stores) ? warehouse.stores : [],
    source_periods: Object.fromEntries(Object.entries(sources).map(([name, source]) => [name, source.meta.period])),
    inventory_data_through: current?.data_through || null };
};
