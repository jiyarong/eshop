module Ec
  class SkuInventoryOverviewBatchQuery
    RECEIVED_STATUSES = %w[received closed].freeze
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze
    ORDER_ITEM_JOIN = SalesFunnelReports::SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN

    def initialize(skus:)
      @skus = skus.to_a
      @sku_codes = @skus.map { |sku| sku.sku_code.to_s.upcase }.uniq
    end

    def call
      return {} if @sku_codes.empty?

      received = received_quantities
      sold = sales_quantities
      returned = return_quantities
      removals = ozon_removal_quantities
      incoming = incoming_quantities
      platform = platform_quantities

      @sku_codes.index_with do |sku_code|
        book_stock = received.fetch(sku_code, 0) - sold.fetch(sku_code, 0) +
          returned.fetch(sku_code, 0) - removals.fetch(sku_code, 0)
        {
          book_stock:,
          platform_stock: platform.fetch(sku_code, 0),
          incoming_quantity: incoming.fetch(sku_code, 0)
        }
      end
    end

    private

    def received_quantities
      Ec::SkuBatch.where(sku_code: @sku_codes, status: RECEIVED_STATUSES)
        .group(:sku_code).sum(:received_quantity).transform_keys(&:to_s).transform_values(&:to_i)
    end

    def incoming_quantities
      Ec::SkuBatch.where(sku_code: @sku_codes, status: INCOMING_STATUSES)
        .group(:sku_code).sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL))
        .transform_keys(&:to_s).transform_values(&:to_i)
    end

    def sales_quantities
      Ec::OrderItem.joins(:order).joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .where.not(ec_orders: { order_status: "cancelled" })
        .group("ec_sku_products.sku_code").sum(:quantity)
        .transform_keys(&:to_s).transform_values(&:to_i)
    end

    def return_quantities
      Ec::ReturnItem.joins(:sku_product, return: :order)
        .where(ec_sku_products: { sku_code: @sku_codes }, restockable: true)
        .where.not(ec_orders: { order_status: "cancelled" })
        .group("ec_sku_products.sku_code").sum(:quantity)
        .transform_keys(&:to_s).transform_values(&:to_i)
    end

    def platform_quantities
      Ec::SkuInventoryLevel.latest
        .where(sku_code: @sku_codes, fulfillment_type: %w[fbo fbw])
        .group(:sku_code).sum(:quantity).transform_keys(&:to_s).transform_values(&:to_i)
    end

    def ozon_removal_quantities
      products = Ec::SkuProduct.includes(:store).where(sku_code: @sku_codes, platform: "ozon").to_a
      sku_codes_by_key = products.group_by { |product| [product.store.ozon_raw_account_id, product.platform_sku_id.to_s] }
        .transform_values { |rows| rows.map(&:sku_code).uniq }
      account_ids = sku_codes_by_key.keys.map(&:first).compact.uniq
      platform_sku_ids = sku_codes_by_key.keys.map(&:last).reject(&:blank?).uniq
      return {} if account_ids.empty? || platform_sku_ids.empty?

      result = Hash.new(0)
      RawOzon::RemovalItem.deducting_return_inventory
        .where(account_id: account_ids, sku: platform_sku_ids)
        .pluck(:account_id, :sku, :quantity)
        .each do |account_id, platform_sku_id, quantity|
          sku_codes_by_key.fetch([account_id, platform_sku_id.to_s], []).each do |sku_code|
            result[sku_code] += quantity.to_i
          end
        end
      result
    end
  end
end
