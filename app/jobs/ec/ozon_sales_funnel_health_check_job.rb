module Ec
  class OzonSalesFunnelHealthCheckJob < ApplicationJob
    DATA_DELAY_DAYS = 2
    WINDOW_DAYS = 3

    queue_as :default

    def perform
      Ec::Store.where(platform: "ozon", is_active: true).find_each do |store|
        check_store(store)
      rescue StandardError => error
        Rails.logger.error("[OzonSalesFunnelHealthCheckJob] store=#{store.id} #{error.class}: #{error.message}")
      end
    end

    private

    def check_store(store)
      account_id = store.ozon_raw_account_id
      return if account_id.blank?

      # Exclude today and allow two complete days for platform data to settle.
      as_of = Time.current.in_time_zone("Asia/Shanghai").to_date - (DATA_DELAY_DAYS + 1).days
      current_start = as_of - (WINDOW_DAYS - 1).days
      baseline_start = current_start - WINDOW_DAYS.days
      current = aggregate(account_id, current_start, as_of)
      baseline = aggregate(account_id, baseline_start, current_start - 1.day)
      products = Ec::SkuProduct.where(store_id: store.id, platform: "ozon")
        .where.not(platform_sku_id: [nil, ""])
        .select(:sku_code, :platform_sku_id)

      observations = products.filter_map do |product|
        current_row = current[product.platform_sku_id.to_s]
        baseline_row = baseline[product.platform_sku_id.to_s]
        next unless current_row && baseline_row

        { sku_code: product.sku_code, current: current_row, baseline: baseline_row }
      end
      Ec::FunnelAnomalyNotifier.call(observations: observations, store: store, as_of: as_of)
    end

    def aggregate(account_id, from_date, to_date)
      RawOzon::SalesFunnelDaily
        .where(account_id: account_id, stat_date: from_date..to_date)
        .select("sku, SUM(hits_view_pdp) AS views, SUM(hits_tocart_pdp) AS carts, SUM(ordered_units) AS orders, SUM(revenue) AS revenue")
        .group(:sku)
        .having("COUNT(*) = ?", WINDOW_DAYS)
        .each_with_object({}) do |row, result|
          result[row.sku.to_s] = {
            "views" => row.attributes["views"],
            "carts" => row.attributes["carts"],
            "orders" => row.attributes["orders"],
            "revenue" => row.attributes["revenue"]
          }
        end
    end
  end
end
