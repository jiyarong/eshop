module Ec
  class PlatformInboundInventoryQuery
    OZON_INBOUND_STATUSES = %w[IN_TRANSIT].freeze
    WB_INBOUND_STATUS_IDS = [2, 3, 4].freeze

    def initialize(platform:, account:)
      @platform = platform.to_s
      @account = account
    end

    def by_sku_code
      case @platform
      when "wb" then wb_quantities_by_sku_code
      when "ozon" then ozon_quantities_by_sku_code
      else {}
      end
    end

    private

    def wb_quantities_by_sku_code
      nm_to_sku_code = Ec::SkuProduct
        .joins(:store)
        .where(platform: "wb", ec_stores: { wb_raw_account_id: @account.id })
        .pluck(:product_id, :sku_code)
        .each_with_object({}) { |(product_id, sku_code), hash| hash[product_id.to_s] = sku_code }

      return {} if nm_to_sku_code.empty?

      rows = RawWb::SupplyItem
        .joins(
          <<~SQL.squish
            INNER JOIN raw_wb_supplies
              ON raw_wb_supplies.account_id = raw_wb_supply_items.account_id
             AND (
               raw_wb_supplies.wb_supply_id = raw_wb_supply_items.wb_supply_id
               OR raw_wb_supplies.preorder_id::text = raw_wb_supply_items.wb_supply_id
             )
          SQL
        )
        .where(account_id: @account.id, nm_id: nm_to_sku_code.keys)
        .where("raw_wb_supplies.status_id IN (?)", WB_INBOUND_STATUS_IDS)
        .group(:nm_id)
        .sum("GREATEST(raw_wb_supply_items.quantity - raw_wb_supply_items.accepted_qty, 0)")

      rows.each_with_object(Hash.new(0)) do |(nm_id, quantity), hash|
        sku_code = nm_to_sku_code[nm_id.to_s]
        hash[sku_code] += quantity.to_i if sku_code.present?
      end
    end

    def ozon_quantities_by_sku_code
      platform_sku_to_sku_code = Ec::SkuProduct
        .joins(:store)
        .where(platform: "ozon", ec_stores: { ozon_raw_account_id: @account.id })
        .pluck(:platform_sku_id, :sku_code)
        .each_with_object({}) { |(platform_sku_id, sku_code), hash| hash[platform_sku_id.to_s] = sku_code }

      return {} if platform_sku_to_sku_code.empty?

      RawOzon::SupplyOrder
        .where(account_id: @account.id, status: OZON_INBOUND_STATUSES)
        .where.not(items: nil)
        .each_with_object(Hash.new(0)) do |order, hash|
          order.items.to_h.each do |platform_sku_id, quantity|
            sku_code = platform_sku_to_sku_code[platform_sku_id.to_s]
            hash[sku_code] += quantity.to_i if sku_code.present?
          end
        end
    end
  end
end
