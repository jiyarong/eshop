export const code = async ({ sources: s, search_details: search }) => {
  const parse = (v, fallback) => typeof v === 'string' ? JSON.parse(v) : (v ?? fallback);
  const text = v => String(v ?? '').replace(/<br\s*\/?\s*>/gi, '\n').replace(/<[^>]+>/g, '').trim();
  const flatten = list => parse(list, []).flatMap(a => [a, ...flatten(a.attributes ?? [])]);
  const richText = v => {
    if (Array.isArray(v)) return v.map(richText).filter(Boolean).join('\n');
    if (v && typeof v === 'object') return Object.entries(v).map(([k, x]) => /^(text|title|content|caption|description|items|blocks|widgets|children)$/i.test(k) ? richText(x) : (typeof x === 'object' ? richText(x) : '')).filter(Boolean).join('\n');
    return typeof v === 'string' ? text(v) : '';
  };
  for (const key of ['base', 'funnel', 'search', 'inventory']) {
    const meta = s[key]?.meta;
    if (meta?.schema_version !== 3 || meta.sku_code !== s.config.sku_code) throw new Error(`${key}: SKU/schema mismatch`);
    if (meta.period.as_of !== s.base.meta.period.as_of || meta.period.time_zone !== s.base.meta.period.time_zone) throw new Error(`${key}: date/time zone mismatch`);
  }
  for (const [key, source] of Object.entries({ listing: s.listing, catalog: s.catalog, search })) {
    if (source?.success !== true || !Array.isArray(source.rows) || source.pagination?.has_more) throw new Error(`${key}: incomplete query result; narrow the period or add pagination`);
  }
  if (!/^[A-Z0-9_-]+$/.test(s.config.sku_code)) throw new Error('SKU must use letters, digits, underscores or hyphens');
  const catalog = s.catalog.rows.map(a => ({
    id: Number(a.attribute_id), complex_id: Number(a.attribute_complex_id), name: a.name,
    category_id: a.description_category_id, type_id: a.type_id, required: a.is_required,
    input_mode: Number(a.dictionary_id) > 0 ? 'dictionary' : 'free_input',
    max_count: Number(a.max_value_count) > 0 ? Number(a.max_value_count) : (a.is_collection ? null : 1),
    options: parse(a.options, []), synced_at: a.synced_at
  }));
  const terms = new Map();
  for (const row of [...search.rows].sort((a, b) => String(a.synced_at).localeCompare(String(b.synced_at)))) {
    const key = JSON.stringify([row.sku_product_id, row.period_from, row.period_to, row.query]);
    terms.set(key, { sku_product_id: row.sku_product_id, query: row.query, period_from: row.period_from,
      period_to: row.period_to, unique_search_users: row.unique_search_users, unique_view_users: row.unique_view_users,
      order_count: row.order_count, gmv: row.gmv, position: row.position,
      source_rankings: [...(terms.get(key)?.source_rankings ?? []), row.top_order_by], synced_at: row.synced_at });
  }
  const listings = s.listing.rows.map(row => {
    if (row.sku_code !== s.config.sku_code || !row.source_found || !row.attributes_synced || !row.title) throw new Error(`Listing ${row.sku_product_id}: missing critical source data`);
    const attributes = flatten(row.product_attributes).concat(flatten(row.complex_attributes));
    const value = id => attributes.filter(a => Number(a.id) === id).flatMap(a => a.values ?? []).map(v => v.value).join('\n');
    const definitions = catalog.filter(a => a.category_id === row.description_category_id && a.type_id === row.type_id);
    if (!definitions.length) throw new Error(`Listing ${row.sku_product_id}: missing category definitions`);
    const current = definitions.map(a => ({ ...a, current_values: attributes.filter(v => Number(v.id) === a.id && Number(v.complex_id ?? 0) === a.complex_id).flatMap(v => v.values ?? []).map(v => ({ id: v.dictionary_value_id || null, value: v.value })) }));
    const unknown = attributes.filter(a => !definitions.some(d => d.id === Number(a.id))).map(a => ({ id: Number(a.id), name: a.name, input_mode: 'unknown', options: [], max_count: null, current_values: a.values ?? [] }));
    const richRaw = value(11254);
    let rich = null;
    try { rich = richRaw ? JSON.parse(richRaw) : null; } catch { rich = { text: richRaw }; }
    const images = [].concat(parse(row.primary_image, []), parse(row.images, [])).map(x => typeof x === 'string' ? x : x?.url).filter(x => /^https:\/\//.test(x ?? ''));
    return {
      sku_product_id: row.sku_product_id, store_id: row.store_id, store_name: row.store_name,
      product_id: row.product_id, category_id: row.description_category_id, type_id: row.type_id,
      product_info: row.product_info || null, product_name: row.product_name,
      title: row.title, description: text(row.description || value(4191)), rich_content: rich,
      rich_content_text: richText(rich), rich_content_configured: Boolean(richRaw),
      primary_image_url: images[0] || null, product_synced_at: row.product_synced_at,
      attributes_synced_at: row.attributes_synced_at, attributes: current.concat(unknown),
      funnel: s.funnel.listings.filter(l => l.platform === 'ozon' && l.sku_product_id === row.sku_product_id).flatMap(l => l.rows_per_week),
      search_terms: [...terms.values()].filter(t => t.sku_product_id === row.sku_product_id),
      search_summary: s.search.weeks.map(w => ({ from: w.period_from, to: w.period_to, is_partial: w.is_partial, stores: w.stores.filter(st => st.platform === 'ozon' && st.store_id === row.store_id) }))
    };
  });
  if (!listings.length) throw new Error('No active Ozon Listing found');
  return { sku_code: s.config.sku_code, grade: s.base.base.current_grade ?? null, stage: s.base.base.current_stage ?? null,
    as_of: s.base.meta.period.as_of, time_zone: s.base.meta.period.time_zone, listings,
    inventory: s.inventory.inventory.current_inventory_info, periods: { funnel: s.funnel.meta.period, search: s.search.meta.period } };
};
