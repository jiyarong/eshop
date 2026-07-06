require "set"

module Ec
  class SkuPeriodProfitBreakdown
    DEFAULT_WB_RATE_CNY_RUB = 11.0
    DEFAULT_WB_RATE_BYN_RUB = 3.5

    def initialize(sku:, from_date:, to_date:, time_zone:, wb_attributions: nil, ozon_attributions: nil)
      @sku = sku
      @from_date = from_date
      @to_date = to_date
      @time_zone = time_zone
      @wb_attributions = wb_attributions
      @ozon_attributions = ozon_attributions
    end

    def call
      wb = aggregate(
        rows: wb_attributions,
        matcher: method(:wb_row_match?),
        mappings: {
          sales_quantity: :sales_qty,
          return_quantity: :return_qty,
          net_sales_quantity: :net_qty,
          operating_net_profit_cny: :pre_tax
        }
      )
      ozon = aggregate(
        rows: ozon_attributions,
        matcher: method(:ozon_row_match?),
        mappings: {
          sales_quantity: :order_count,
          return_quantity: :return_count,
          net_sales_quantity: :net_sales_count,
          operating_net_profit_cny: :pre_tax_profit
        }
      )

      {
        platforms: {
          wb: wb,
          ozon: ozon
        },
        total: sum_rows(wb, ozon)
      }
    end

    private

    def aggregate(rows:, matcher:, mappings:)
      Array(rows).each_with_object(zero_row) do |row, totals|
        next unless matcher.call(row)

        mappings.each do |target_key, source_key|
          totals[target_key] += source_value_for(target_key, row[source_key])
        end
      end
    end

    def zero_row
      {
        sales_quantity: 0,
        return_quantity: 0,
        net_sales_quantity: 0,
        operating_net_profit_cny: BigDecimal("0")
      }
    end

    def sum_rows(*rows)
      rows.compact.each_with_object(zero_row) do |row, totals|
        totals[:sales_quantity] += row[:sales_quantity]
        totals[:return_quantity] += row[:return_quantity]
        totals[:net_sales_quantity] += row[:net_sales_quantity]
        totals[:operating_net_profit_cny] += row[:operating_net_profit_cny]
      end
    end

    def sku_match?(value)
      value.to_s.casecmp?(@sku.sku_code.to_s)
    end

    def source_value_for(target_key, value)
      return BigDecimal("0") if target_key == :operating_net_profit_cny && value.blank?
      return BigDecimal(value.to_s) if target_key == :operating_net_profit_cny

      value.to_i
    end

    def wb_row_match?(row)
      return true if wb_product_ids.include?(row[:nm_id].to_s)

      sku_match?(row[:vendor_code]) || sku_match?(row[:sku_code])
    end

    def ozon_row_match?(row)
      return true if ozon_platform_sku_ids.include?(row[:ozon_sku_id].to_s)

      sku_match?(row[:sku_code]) || sku_match?(row[:vendor_code])
    end

    def wb_attributions
      return @wb_attributions if @wb_attributions

      wb_account_ids.filter_map do |account_id|
        next if account_id.blank?

        Ec::WbProfitAttribution.new(
          account_id: account_id,
          from_date: @from_date,
          to_date: @to_date,
          rate_cny_rub: DEFAULT_WB_RATE_CNY_RUB,
          rate_byn_rub: DEFAULT_WB_RATE_BYN_RUB
        ).call.results
      end.flatten
    end

    def ozon_attributions
      return @ozon_attributions if @ozon_attributions

      ozon_account_ids.filter_map do |account_id|
        next if account_id.blank?

        Ec::OzonProfitAttribution.new(
          account_id: account_id,
          from_date: @from_date,
          to_date: @to_date
        ).call.results
      end.flatten
    end

    def bound_stores
      return [] unless @sku.respond_to?(:sku_products)

      @bound_stores ||= begin
        stores = @sku.sku_products.includes(:store).filter_map(&:store)

        stores.uniq do |store|
          store.respond_to?(:id) && store.id.present? ? [store.class.name, store.id] : store
        end
      end
    end

    def bound_sku_products
      return [] unless @sku.respond_to?(:sku_products)

      @bound_sku_products ||= @sku.sku_products.includes(:store).filter_map do |sku_product|
        next unless sku_product.respond_to?(:store)
        next if sku_product.store.blank?

        sku_product
      end
    end

    def wb_product_ids
      @wb_product_ids ||= bound_sku_products.filter_map do |sku_product|
        next unless sku_product.respond_to?(:platform)
        next unless sku_product.platform.to_s.casecmp?("wb")
        next unless sku_product.respond_to?(:product_id)
        next if sku_product.product_id.blank?

        sku_product.product_id.to_s
      end.to_set
    end

    def ozon_platform_sku_ids
      @ozon_platform_sku_ids ||= bound_sku_products.filter_map do |sku_product|
        next unless sku_product.respond_to?(:platform)
        next unless sku_product.platform.to_s.casecmp?("ozon")
        next unless sku_product.respond_to?(:platform_sku_id)
        next if sku_product.platform_sku_id.blank?

        sku_product.platform_sku_id.to_s
      end.to_set
    end

    def wb_account_ids
      @wb_account_ids ||= bound_stores.filter_map(&:wb_raw_account_id).uniq
    end

    def ozon_account_ids
      @ozon_account_ids ||= bound_stores.filter_map(&:ozon_raw_account_id).uniq
    end
  end
end
