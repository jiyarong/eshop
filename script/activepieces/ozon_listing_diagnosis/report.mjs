export const code = async ({ context: c, policy, attributes, text, config }) => {
  const listings = c.listings.map(l => {
    const a = attributes.listings.find(a => a.sku_product_id === l.sku_product_id);
    const t = text.listings.find(t => t.sku_product_id === l.sku_product_id);
    const p = policy.listings.find(p => p.sku_product_id === l.sku_product_id);
    const problems = a.problems.concat(t.problems).sort((a, b) => a.priority.localeCompare(b.priority));
    const p0 = problems.filter(p => p.priority === 'P0').length, p1 = problems.filter(p => p.priority === 'P1').length;
    const incomplete = a.assessment === 'insufficient_data' || [t.title, t.description].some(m => m.quality === 'insufficient_data');
    const status = p0 ? 'has_error' : p1 ? 'needs_optimization' : incomplete ? null : 'healthy';
    const limitations = [...new Set(p.warnings.concat(a.limitations, t.limitations))];
    return { sku_product_id: l.sku_product_id, store_name: l.store_name, product_id: l.product_id,
      status, audit_status: incomplete ? 'insufficient_data' : limitations.length ? 'partial' : 'complete',
      p0_count: p0, p1_count: p1, attribute_change_count: a.actions.length,
      title_action: t.title.action, description_action: t.description.action, rich_content_action: t.rich_content.action,
      funnel_anomaly: p.funnel_anomaly, seo_traffic_quality: t.seo.traffic_quality,
      summary: [a.summary, t.summary].filter(Boolean).join('\n'),
      top_issues: problems.length ? problems.slice(0, 3).map(p => `${p.priority}：${p.recommendation}`) : t.top_issues,
      problems, attribute_actions: a.actions.map(action => ({ ...action, current_values: l.attributes.find(a => a.id === action.attribute_id && a.complex_id === (action.complex_id ?? 0))?.current_values ?? [] })),
      title: t.title, description: t.description, rich_content: t.rich_content,
      funnel_attribution: t.funnel_attribution, seo: t.seo, limitations,
      latest_complete_funnel: p.latest_complete_period, current_partial_funnel: p.current_partial_period,
      source_timestamps: { product: l.product_synced_at, attributes: l.attributes_synced_at } };
  });
  const sum = k => listings.reduce((n, l) => n + l[k], 0);
  const status = sum('p0_count') ? 'has_error' : sum('p1_count') ? 'needs_optimization' : listings.some(l => !l.status) ? null : 'healthy';
  const metrics = { sku_code: c.sku_code, grade: c.grade, stage: c.stage, status,
    audit_status: listings.some(l => l.audit_status === 'insufficient_data') ? 'insufficient_data' : listings.some(l => l.audit_status === 'partial') ? 'partial' : 'complete',
    listing_count: listings.length, p0_count: sum('p0_count'), p1_count: sum('p1_count'),
    attribute_change_count: sum('attribute_change_count'), title_rewrite_count: listings.filter(l => l.title_action === 'REWRITE').length,
    description_rewrite_count: listings.filter(l => l.description_action === 'REWRITE').length,
    rich_content_rewrite_count: listings.filter(l => l.rich_content_action === 'REWRITE').length,
    funnel_anomaly_count: policy.funnel_anomaly_count, verified_irrelevant_term_count: listings.reduce((n, l) => n + l.seo.verified_terms.length, 0) };
  const lines = [`# Ozon Listing诊断：${c.sku_code}`, `规则：${config.rule_version}；Grade/Stage：${c.grade}/${c.stage}；日期：${c.as_of}（${c.time_zone}）`, `总状态：${status ?? 'insufficient_data'}；P0：${metrics.p0_count}；P1：${metrics.p1_count}`];
  for (const l of listings) {
    lines.push(`\n## ${l.store_name}（Listing ${l.sku_product_id}）`, l.summary, `Title: ${l.title_action}；Description: ${l.description_action}；Rich-content: ${l.rich_content_action}`, l.funnel_attribution.explanation, `SEO：${l.seo.traffic_quality} — ${l.seo.explanation}`);
    for (const p of l.problems) lines.push(`\n- **${p.priority} / ${p.defect_type}**：${p.current_evidence}\n  依据：${p.fact_evidence}\n  影响：${p.impact}\n  建议：${p.recommendation}`);
    if (!l.problems.length) lines.push('No significant Listing issue found.');
    if (!l.attribute_actions.length) lines.push('Attributes: KEEP');
    if (l.attribute_actions.length) {
      const cell = v => String(v).replace(/\|/g, '\\|').replace(/\n/g, '<br>');
      lines.push('\n| 店铺 | 属性 | 当前值 | 建议最终值 | 理由 |', '| --- | --- | --- | --- | --- |');
      for (const a of l.attribute_actions) lines.push(`| ${cell(l.store_name)} | ${cell(a.attribute_name ?? a.attribute_id)} | ${cell(a.current_values.map(v => v.value).join('、'))} | ${cell(a.suggested_values.map(v => v.value).join('、'))} | ${cell(a.reason)} |`);
    }
    for (const k of ['title', 'description', 'rich_content']) if (l[k].action === 'REWRITE') lines.push(`\n### ${k}\n${l[k].recommended_ru}\n\n中文：${l[k].recommended_zh}`);
    lines.push('\n### 最小动作清单');
    if (!l.problems.length) lines.push('No action required.');
    for (const p of l.problems) lines.push(`- ${p.priority}：${p.recommendation}`);
    if (l.limitations.length) lines.push(`\n数据限制：${l.limitations.join('；')}`);
  }
  return { metrics, listings, markdown: lines.join('\n'), llm: { provider: config.ai_provider, model: config.model, action: 'extractStructuredData' }, rule_version: config.rule_version, as_of: c.as_of, time_zone: c.time_zone };
};
