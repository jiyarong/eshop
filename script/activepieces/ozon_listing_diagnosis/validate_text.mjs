export const code = async ({ diagnosis: d, context: c, policy }) => {
  if (!d || d.sku_code !== c.sku_code || !Array.isArray(d.listings) || d.listings.length !== c.listings.length) throw new Error('Text diagnosis SKU/Listing coverage mismatch');
  const ids = new Set();
  for (const r of d.listings) {
    const l = c.listings.find(l => l.sku_product_id === r.sku_product_id);
    const p = policy.listings.find(p => p.sku_product_id === r.sku_product_id);
    if (!l || ids.has(l.sku_product_id) || !Array.isArray(r.problems) || !Array.isArray(r.limitations)) throw new Error('Invalid text Listing coverage');
    ids.add(l.sku_product_id);
    const issueIds = new Set();
    for (const issue of r.problems) {
      if (!issue.id || issueIds.has(issue.id) || !['title', 'description', 'rich_content', 'seo'].includes(issue.module) || !['P0', 'P1'].includes(issue.priority) || issue.confidence !== 'high' || !issue.fact_evidence || !issue.impact || !issue.recommendation) throw new Error('Text issue lacks high confidence or evidence');
      const source = issue.module === 'seo' ? JSON.stringify(l.search_terms) : issue.module === 'rich_content' ? l.rich_content_text : l[issue.module];
      if (!(issue.current_evidence === '__EMPTY__' ? !source : issue.current_evidence && source.includes(issue.current_evidence))) throw new Error('Text evidence is not from this Listing/module');
      issueIds.add(issue.id);
    }
    for (const module of ['title', 'description', 'rich_content']) {
      const m = r[module];
      if (!m || !['pass', 'fail', 'insufficient_data', 'not_configured'].includes(m.quality) || !['KEEP', 'REWRITE'].includes(m.action) || !m.reason) throw new Error(`Invalid ${module} assessment`);
      const issues = r.problems.filter(i => i.module === module);
      if (m.action === 'REWRITE') {
        if (!issues.length || !m.recommended_ru || !m.recommended_zh) throw new Error('Rewrite needs evidence and complete Russian/Chinese copy');
        if (m.quality === 'pass' && p.text_strategy === 'pass_then_keep') throw new Error('Passing B/C/CLR text must KEEP');
      }
      if (m.quality === 'fail' && m.action !== 'REWRITE') throw new Error('Failed text needs a complete rewrite');
      if (m.quality === 'insufficient_data' && (m.action !== 'KEEP' || issues.length)) throw new Error('Missing evidence cannot become a modification task');
    }
    if (!l.rich_content_configured && (r.rich_content.quality !== 'not_configured' || r.rich_content.action !== 'KEEP')) throw new Error('Unconfigured rich content must KEEP');
    if (!r.funnel_attribution?.explanation || typeof r.funnel_attribution.listing_explains_anomaly !== 'boolean') throw new Error('Missing funnel attribution');
    if (r.funnel_attribution.listing_explains_anomaly && (!p.funnel_anomaly || !r.problems.length)) throw new Error('Unsupported funnel attribution');
    if (!r.seo || !['verified_irrelevant', 'no_verified_irrelevant', 'insufficient_data'].includes(r.seo.traffic_quality) || !Array.isArray(r.seo.verified_terms)) throw new Error('Invalid SEO assessment');
    if (!l.search_terms.length && r.seo.traffic_quality !== 'insufficient_data') throw new Error('No terms means SEO evidence is unavailable');
    r.seo.verified_terms = r.seo.verified_terms.map(term => typeof term === 'string' ? term : term?.query);
    for (const term of r.seo.verified_terms) if (typeof term !== 'string' || !l.search_terms.some(t => t.query === term)) throw new Error('SEO term absent from source');
    if (r.seo.traffic_quality === 'verified_irrelevant' && (!r.seo.verified_terms.length || !r.problems.some(i => i.module === 'seo'))) throw new Error('Irrelevant SEO traffic needs a verified issue');
    if (!Array.isArray(r.top_issues) || !r.summary) throw new Error('Missing executive summary');
  }
  return d;
};
