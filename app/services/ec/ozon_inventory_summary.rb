module Ec
  # Ozon 三店（FBO）库存汇总
  #
  # 计算逻辑（已与 Inventory_v9 Excel 对比验证，除已删除商品外完全一致）：
  #   送仓总计 = SUM(supply_orders.items[ozon_sku])，status=COMPLETED
  #   FBO库存  = product_stocks.present_fbo（实时快照）
  #   FBO售出  = 送仓总计 − FBO库存
  #   FBS净销量 = posting_items.quantity，posting status=delivered
  #
  # SKU 映射链：
  #   supply_orders.items key (ozon_sku)
  #     → raw_ozon_products.raw_json['sku'] → offer_id (Article)
  #
  # Usage:
  #   result = Ec::OzonInventorySummary.new.call
  #   result.rows      # Array of OzonInventoryRow
  #   result.by_article("JZJJ-001")  # 查单个 Article
  #
  # 单账号用法：
  #   Ec::OzonInventorySummary.new(account_ids: [1]).call

  OzonInventoryRow = Struct.new(
    :article, :store_name, :account_id,
    :fbo_supply, :fbo_stock, :fbo_sold, :fbs_net,
    keyword_init: true
  )

  class OzonInventorySummary
    # account_id → 店铺名（按实际线上账号）
    STORE_NAMES = {
      1 => "Nevastal",
      3 => "Nevastal2",
      4 => "Domos",
      5 => "Nanokit",
    }.freeze

    def initialize(account_ids: nil)
      @account_ids = account_ids || STORE_NAMES.keys
    end

    def call
      @rows = []
      build_sku_maps
      @account_ids.each { |aid| process_account(aid) }
      self
    end

    def rows
      @rows
    end

    def by_article(article)
      @rows.select { |r| r.article == article }
    end

    def to_h
      @rows.group_by(&:article).transform_values do |store_rows|
        store_rows.map { |r| [r.store_name, r.to_h.except(:article, :store_name, :account_id)] }.to_h
      end
    end

    private

    # ozon_sku(string) → offer_id(Article)
    # ozon_sku(string) → ozon_product_id
    def build_sku_maps
      @sku_to_article = {}
      @sku_to_pid     = {}
      RawOzon::Product.find_each do |p|
        ozon_sku = p.raw_json["sku"].to_s
        next if ozon_sku.blank?
        @sku_to_article[ozon_sku] = p.offer_id
        @sku_to_pid[ozon_sku]     = p.ozon_product_id
      end
    end

    def process_account(account_id)
      store_name = STORE_NAMES[account_id] || "Account##{account_id}"

      supply_totals = build_supply_totals(account_id)
      fbs_totals    = build_fbs_totals(account_id)
      all_skus      = (supply_totals.keys + fbs_totals.keys).uniq
      stock_map     = build_stock_map(account_id, all_skus)

      all_skus.each do |ozon_sku|
        article = @sku_to_article[ozon_sku]
        next if article.blank?

        supply = supply_totals[ozon_sku] || 0
        pid    = @sku_to_pid[ozon_sku]
        stock  = pid ? (stock_map[pid] || 0) : 0
        fbs    = fbs_totals[ozon_sku] || 0

        @rows << OzonInventoryRow.new(
          article:    article,
          store_name: store_name,
          account_id: account_id,
          fbo_supply: supply,
          fbo_stock:  stock,
          fbo_sold:   supply - stock,
          fbs_net:    fbs,
        )
      end
    end

    def build_supply_totals(account_id)
      totals = Hash.new(0)
      RawOzon::SupplyOrder.where(account_id: account_id, status: "COMPLETED").each do |so|
        so.items.each { |sku, qty| totals[sku.to_s] += qty.to_i }
      end
      totals
    end

    def build_stock_map(account_id, ozon_skus)
      product_ids = ozon_skus.map { |s| @sku_to_pid[s] }.compact
      return {} if product_ids.empty?
      RawOzon::ProductStock
        .where(account_id: account_id, ozon_product_id: product_ids)
        .pluck(:ozon_product_id, :present_fbo)
        .to_h
    end

    # DESIGN_v9 §3.3: delivered(+qty) + cancelled(-qty) = 净销量
    def build_fbs_totals(account_id)
      totals = Hash.new(0)

      delivered = RawOzon::PostingFbs
        .where(account_id: account_id, status: "delivered")
        .pluck(:posting_number)
      if delivered.any?
        RawOzon::PostingItem
          .where(account_id: account_id, posting_type: "fbs", posting_number: delivered)
          .pluck(:ozon_sku, :quantity)
          .each { |sku, qty| totals[sku.to_s] += qty.to_i }
      end

      cancelled = RawOzon::PostingFbs
        .where(account_id: account_id, status: "cancelled")
        .pluck(:posting_number)
      if cancelled.any?
        RawOzon::PostingItem
          .where(account_id: account_id, posting_type: "fbs", posting_number: cancelled)
          .pluck(:ozon_sku, :quantity)
          .each { |sku, qty| totals[sku.to_s] -= qty.to_i }
      end

      totals
    end
  end
end
