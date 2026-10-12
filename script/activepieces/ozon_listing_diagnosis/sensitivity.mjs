export const code = async ({ context: d, config: c }) => {
  const metrics = ['ozon_click_rate', 'cart_rate', 'visit_to_conversion_rate'];
  const listings = d.listings.map(l => {
    const completed = l.funnel.filter(p => p.period_to < d.as_of).sort((a, b) => b.period_to.localeCompare(a.period_to));
    const [latest, previous] = completed;
    const alerts = [];
    if (latest && previous && latest.values.product_card_views >= c.min_funnel_views && previous.values.product_card_views >= c.min_funnel_views) {
      for (const metric of metrics) {
        const a = latest.values[metric], b = previous.values[metric];
        if (a !== null && a !== undefined && b > 0 && a / b <= 1 - c.funnel_relative_drop) alerts.push({ metric, latest: a, previous: b, relative_drop: 1 - a / b });
      }
    }
    const high = d.stage !== 'CLR' && (['S', 'A'].includes(d.grade) || d.stage === 'NEW' || alerts.length > 0);
    const warnings = [];
    if (!d.grade || !d.stage) warnings.push('Grade/Stage missing; limit conclusions');
    if (!l.product_info) warnings.push('No technical product_info; do not invent facts');
    if (!l.description) warnings.push('Description absent from synced source; cannot confirm live absence');
    if (!l.search_terms.length) warnings.push('No actual query terms; SEO semantic attribution unavailable');
    if (l.attributes.some(a => a.input_mode === 'dictionary' && !a.options.length)) warnings.push('Some official dictionaries are not locally cached; no new values may be invented');
    return { sku_product_id: l.sku_product_id, grade: d.grade, stage: d.stage,
      text_strategy: high ? 'pass_then_high_value_only' : 'pass_then_keep',
      attribute_strategy: d.stage === 'CLR' ? 'correct_errors_and_relevant_attributes' : 'structured_optimal',
      funnel_anomaly: alerts.length > 0, funnel_alerts: alerts,
      latest_complete_period: latest ?? null, current_partial_period: l.funnel.find(p => p.period_from <= d.as_of && p.period_to >= d.as_of) ?? null,
      warnings, attribution_rule: 'A funnel anomaly raises inspection sensitivity and never proves a Listing defect. Partial-week conversions are provisional.' };
  });
  return { listings, funnel_anomaly_count: listings.filter(l => l.funnel_anomaly).length };
};
