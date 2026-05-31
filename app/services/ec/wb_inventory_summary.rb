module Ec
  # WB 两店（FBW）库存汇总
  #
  # 计算逻辑（已与线上数据验证关联链）：
  #   送仓总计 = SUM(supply_items.accepted_qty) 按 nm_id 聚合
  #   FBW库存  = SUM(raw_wb_stocks.quantity) 按 nm_id 关联（barcode→product_skus→products）
  #   FBW售出  = 送仓总计 − FBW当前库存
  #
  # SKU 映射链：
  #   raw_wb_stocks.barcode
  #     → raw_wb_product_skus.barcode → product_id
  #     → raw_wb_products.id → nm_id, vendor_code
  #
  # Usage:
  #   result = Ec::WbInventorySummary.new.call
  #   result.rows      # Array of WbInventoryRow
  #   result.by_vendor("KJ-228-BK")

  WbInventoryRow = Struct.new(
    :nm_id, :vendor_code, :store_name, :account_id,
    :fbw_supply, :fbw_stock, :fbw_sold, :fbs,
    keyword_init: true
  )

  class WbInventorySummary
    STORE_NAMES = {
      2 => "TaxiLink",
      3 => "WorldChoice",
    }.freeze

    def initialize(account_ids: nil)
      @account_ids = account_ids || STORE_NAMES.keys
    end

    def call
      @rows = []
      @account_ids.each { |aid| process_account(aid) }
      self
    end

    def rows
      @rows
    end

    def by_vendor(vendor_code)
      @rows.select { |r| r.vendor_code == vendor_code }
    end

    def to_h
      @rows.group_by(&:vendor_code).transform_values do |store_rows|
        store_rows.map { |r| [r.store_name, r.to_h.except(:vendor_code, :store_name, :account_id)] }.to_h
      end
    end

    private

    def process_account(account_id)
      store_name = STORE_NAMES[account_id] || "Account##{account_id}"

      supply_totals = build_supply_totals(account_id)
      stock_map     = build_stock_map(account_id)
      nm_to_vendor  = build_nm_to_vendor(account_id)
      fbs_totals    = build_fbs_totals(account_id)

      all_nm_ids = (supply_totals.keys + stock_map.keys + fbs_totals.keys).uniq
      all_nm_ids.each do |nm_id|
        vendor = nm_to_vendor[nm_id]
        next if vendor.blank?

        supply = supply_totals[nm_id] || 0
        stock  = stock_map[nm_id] || 0
        fbs    = fbs_totals[nm_id] || 0

        @rows << WbInventoryRow.new(
          nm_id:       nm_id,
          vendor_code: vendor,
          store_name:  store_name,
          account_id:  account_id,
          fbw_supply:  supply,
          fbw_stock:   stock,
          fbw_sold:    supply - stock,
          fbs:         fbs,
        )
      end
    end

    def build_supply_totals(account_id)
      RawWb::SupplyItem
        .where(account_id: account_id)
        .group(:nm_id)
        .sum(:accepted_qty)
    end

    # barcode → product_skus → products → nm_id → sum(quantity)
    def build_stock_map(account_id)
      sql = <<~SQL
        SELECT p.nm_id, SUM(s.quantity) AS total_qty
        FROM raw_wb_stocks s
        JOIN raw_wb_product_skus ps ON ps.barcode = s.barcode
        JOIN raw_wb_products p ON p.id = ps.product_id
        WHERE s.account_id = #{account_id.to_i}
        GROUP BY p.nm_id
      SQL
      rows = ActiveRecord::Base.connection.execute(sql)
      rows.each_with_object({}) { |r, h| h[r["nm_id"].to_i] = r["total_qty"].to_i }
    end

    def build_nm_to_vendor(account_id)
      RawWb::Product
        .where(account_id: account_id)
        .pluck(:nm_id, :vendor_code)
        .to_h { |nm, vc| [nm.to_i, vc] }
    end

    # DESIGN_v9 §3.6: GET /api/v3/orders, deliveryType='fbs', 每个 order 算 1 件
    def build_fbs_totals(account_id)
      RawWb::Order
        .where(account_id: account_id, delivery_type: 'fbs')
        .group(:nm_id)
        .count
        .transform_keys(&:to_i)
    end
  end
end
