module Ec
  class OzonSalesFunnelHealthCheckJob < ApplicationJob
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

      latest_date = RawOzon::SalesFunnelDaily.where(account_id: account_id).maximum(:stat_date)
      return if latest_date.blank?

      current_start = latest_date - 2.days
      baseline_start = latest_date - 5.days
      current = aggregate(account_id, current_start, latest_date)
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
      Ec::FunnelAnomalyNotifier.call(observations: observations, store: store, as_of: latest_date)
    end

    def aggregate(account_id, from_date, to_date)
      RawOzon::SalesFunnelDaily
        .where(account_id: account_id, stat_date: from_date..to_date)
        .select("sku, SUM(hits_view_pdp) AS views, SUM(hits_tocart_pdp) AS carts, SUM(ordered_units) AS orders, SUM(revenue) AS revenue")
        .group(:sku)
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
