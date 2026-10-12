export const code = async ({ data: d }) => {
  const number = v => v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? null : Number(v);
  const channels = [], alerts = [], missing = [];
  for (const listing of d.listings) {
    const p0 = listing.rows_per_week.find(row => row.period_key === 'P0');
    const values = p0?.values || {};
    const warehouse = d.warehouses.find(store => store.store_id === listing.store_id && store.platform === listing.platform && store.data_status === 'available');
    const fbo = number(warehouse?.summary?.available) ?? (listing.platform === 'wb' ? (values.wb_stock ?? null) : null);
    const fbs = number(warehouse?.summary?.fbs_available) ?? (listing.platform === 'wb' ? (values.wb_seller_stock ?? null) : null);
    const demand = (values.orders ?? 0) > 0 || (values.cart_additions ?? 0) > 0;
    let status = fbo === null || fbs === null ? 'insufficient_data' : fbo <= 2 && fbs <= 2 ? 'channel_stockout' : fbo <= 2 && fbs > 2 ? 'fbs_fallback' : 'available';
    if (status === 'insufficient_data') missing.push(`channel_stock:${listing.store_ref}`);
    const top_clusters = (warehouse?.sales_clusters || []).filter(cluster => number(cluster.distribution_gap) > 0)
      .sort((a, b) => b.distribution_gap - a.distribution_gap).slice(0, 5)
      .map(cluster => ({ cluster_name: cluster.cluster_name, suggested_quantity: cluster.distribution_gap }));
    const channel = { platform: listing.platform, store_id: listing.store_id, store_name: listing.store_name, status,
      fbo_stock: fbo, fbs_stock: fbs, stock_source: warehouse ? 'warehouse_recommendation.current' : 'funnel.P0',
      distribution_gap: number(warehouse?.summary?.distribution_gap), top_clusters,
      days_of_stock: number(warehouse?.summary?.days_of_stock), daily_sales: number(warehouse?.summary?.daily_sales) };
    channels.push(channel);
    if (status === 'fbs_fallback') alerts.push({ type: '渠道失衡', level: 'yellow',
      message: `${listing.platform.toUpperCase()} ${listing.store_name}官方仓库存${fbo}件，商品未断货，由白俄本地仓FBS兜底；配送通常慢2～4天，可能影响转化和搜索排位。`,
      advice: '按官方仓分布缺口安排送仓，优先核心销售集群；FBS挂载库存不能跨Listing相加为物理库存。', evidence: channel });
    if (status === 'channel_stockout' && demand) alerts.push({ type: '渠道失衡', level: 'yellow',
      message: `${listing.platform.toUpperCase()} ${listing.store_name}官方仓与FBS均接近售罄，近期仍有销售或加购需求。`,
      advice: d.days_in_stock !== null && d.days_in_stock >= 28 ? '立即从白俄总仓向该渠道配货。' : '核实其他渠道冗余现货，评估跨平台紧急调拨。', evidence: channel });
  }
  if (!d.listings.length) missing.push('channel_listings');
  return { channels, alerts, missing, unallocated_stock: null,
    limitation: '各Listing的FBS可能重复挂载同一白俄物理库存，当前API没有可去重的分配明细，不能用book_stock减Listing现货总和计算未铺发库存。' };
};
