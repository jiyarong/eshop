export const code = async ({ diagnosis: d, context: c }) => {
  if (!d || d.sku_code !== c.sku_code || !Array.isArray(d.listings) || d.listings.length !== c.listings.length) throw new Error('Attribute diagnosis SKU/Listing coverage mismatch');
  const ids = new Set();
  for (const result of d.listings) {
    const l = c.listings.find(l => l.sku_product_id === result.sku_product_id);
    if (!l || ids.has(l.sku_product_id)) throw new Error('Unknown or duplicate Listing in attribute diagnosis');
    ids.add(l.sku_product_id);
    if (!['KEEP', 'CHANGE', 'insufficient_data'].includes(result.assessment) || !Array.isArray(result.problems) || !Array.isArray(result.actions) || !Array.isArray(result.limitations)) throw new Error('Invalid attribute assessment');
    const issues = new Set();
    for (const p of result.problems) {
      const a = l.attributes.find(a => a.id === p.attribute_id && a.complex_id === (p.complex_id ?? 0));
      if (!a || [9048, 12141, 22390, 4180, 4191, 11254].includes(a.id)) throw new Error('Unknown or exempt attribute reported as a problem');
      if (!p.id || issues.has(p.id) || !['P0', 'P1'].includes(p.priority) || p.confidence !== 'high' || !p.fact_evidence || !p.impact || !p.recommendation) throw new Error('Attribute issue lacks high confidence or evidence');
      const current = JSON.stringify(a.current_values);
      if (!(p.current_evidence === '__EMPTY__' ? a.current_values.length === 0 : p.current_evidence && current.includes(p.current_evidence))) throw new Error('Attribute evidence is not from the current Listing');
      issues.add(p.id);
    }
    const actionKeys = new Set();
    for (const action of result.actions) {
      const a = l.attributes.find(a => a.id === action.attribute_id && a.complex_id === (action.complex_id ?? 0));
      const key = `${action.attribute_id}:${action.complex_id ?? 0}`;
      if (!a || actionKeys.has(key) || !issues.has(action.problem_id) || !Array.isArray(action.suggested_values)) throw new Error('Invalid or duplicate attribute action');
      actionKeys.add(key);
      if (a.max_count && action.suggested_values.length > a.max_count) throw new Error(`Attribute ${a.id} exceeds official max_count`);
      if (new Set(action.suggested_values.map(v => `${v.id}:${v.value}`)).size !== action.suggested_values.length) throw new Error('Duplicate suggested values');
      for (const v of action.suggested_values) {
        if (typeof v.value !== 'string' || !v.value.trim()) throw new Error('Empty attribute value');
        if (a.input_mode === 'unknown') throw new Error('Cannot modify an attribute without its official definition');
        if (a.input_mode === 'dictionary' && !a.options.some(o => o.id === v.id && o.value === v.value)) throw new Error(`Attribute ${a.id}: value is outside the official options pool`);
      }
    }
    if (result.assessment === 'KEEP' && (result.problems.length || result.actions.length)) throw new Error('KEEP conflicts with attribute changes');
    if (result.assessment === 'CHANGE' && (!result.problems.length || !result.actions.length)) throw new Error('CHANGE requires evidence and actions');
  }
  return d;
};
