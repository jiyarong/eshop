module RawOzon
  module Ads
    class Sync
      require "zip"

      CPC_SKU_BATCH_SIZE = 10
      CAMPAIGN_DAILY_BATCH_SIZE = 50
      CPC_HISTORY_BATCH_SIZE = 10
      CPC_HISTORY_MAX_DAYS = 62

      def self.run(from_date: Date.yesterday, to_date: Date.yesterday)
        stores = Ec::Store.where(platform: "ozon", is_active: true).where.not(ozon_performance_client_id: nil)
        raise ArgumentError, "No active Ozon stores with Performance credentials found" if stores.none?

        stores.each_with_object({}) do |store, results|
          account = store.raw_ozon_account
          raise "Ec::Store##{store.id} has no linked Ozon account" unless account
          results[store.id] = new(account).run(from_date: from_date, to_date: to_date)
        end
      end

      def initialize(account, client: nil, report_runner: nil)
        @account = account
        @client = client || RawOzon::PerformanceClient.new(account.performance_client_id, account.performance_client_secret)
        @report_runner = report_runner || ReportRunner.new(account: account, client: @client)
      end

      def run(from_date:, to_date:)
        from_date = from_date.to_date
        to_date = to_date.to_date
        raise ArgumentError, "to_date must be on or after from_date" if to_date < from_date

        {
          units: sync_units,
          products: sync_unit_products,
          daily_stats: sync_daily_stats(from_date: from_date, to_date: to_date),
          cpc_sku_stats: sync_cpc_sku_stats(from_date: from_date, to_date: to_date),
          cpo_selected_stats: sync_cpo_selected_stats(from_date: from_date, to_date: to_date),
          cpo_all_stats: sync_cpo_all_stats(from_date: from_date, to_date: to_date)
        }
      end

      def sync_units
        items = Array(@client.get("/api/client/campaign")["list"])
        synced_at = Time.current
        rows = items.map { |item| unit_row(item, synced_at) }
        RawOzon::AdUnit.upsert_all(rows, unique_by: :idx_raw_ozon_ad_units_identity) if rows.any?
        rows.size
      end

      def sync_unit_products
        synced = 0
        product_map = raw_product_map

        cpc_units.where.not(state: "CAMPAIGN_STATE_ARCHIVED").find_each do |unit|
          response = @client.get("/api/client/campaign/#{unit.external_id}/v2/products")
          products = response_array(response)
          synced += upsert_unit_products(unit, products, product_map, source: "cpc")
        end

        if (unit = cpo_selected_unit)
          products = response_array(@client.post("/api/client/campaign/search_promo/v2/products", {}))
          synced += upsert_unit_products(unit, products, product_map, source: "cpo_selected")
        end
        synced
      end

      def sync_daily_stats(from_date:, to_date:)
        units = RawOzon::AdUnit.where(account_id: @account.id)
        total = 0
        units.each_slice(CAMPAIGN_DAILY_BATCH_SIZE) do |batch|
          body = @client.get_csv("/api/client/statistics/daily", {
            campaigns: batch.map(&:external_id).join(","), dateFrom: from_date.to_s, dateTo: to_date.to_s
          })
          unit_map = batch.index_by(&:external_id)
          rows = CsvParser.daily_stats(body).filter_map do |stat|
            unit = unit_map[stat.delete(:external_id).to_s]
            next unless unit
            stat.merge(account_id: @account.id, ad_unit_id: unit.id, cost_model: unit.billing_model || "unknown",
              synced_at: Time.current, created_at: Time.current, updated_at: Time.current)
          end
          upsert_daily_rows(rows)
          total += rows.size
        end
        total
      end

      def sync_cpc_sku_stats(from_date:, to_date:)
        valid_dates = (from_date..to_date).select { |date| [Date.current, Date.yesterday].include?(date) }
        units = cpc_units.where.not(state: "CAMPAIGN_STATE_ARCHIVED").to_a
        total = 0
        product_map = raw_product_map

        valid_dates.each do |date|
          units.each_slice(CPC_SKU_BATCH_SIZE) do |batch|
            response = @client.post("/api/client/statistics/products/sku", {
              campaignIds: batch.map(&:external_id), dateFrom: date.to_s, dateTo: date.to_s
            })
            unit_map = batch.index_by(&:external_id)
            rows = Array(response["rows"]).filter_map do |item|
              unit = unit_map[item["campaignId"].to_s]
              next unless unit && item["sku"].present?
              build_cpc_sku_stat(item, unit, product_map)
            end
            upsert_sku_rows(rows)
            total += rows.size
          end
        end
        total
      end

      def sync_cpc_history_stats(from_date:, to_date:, units: nil)
        from_date = from_date.to_date
        to_date = to_date.to_date
        raise ArgumentError, "to_date must be on or after from_date" if to_date < from_date
        raise ArgumentError, "CPC history report cannot exceed #{CPC_HISTORY_MAX_DAYS} days" if (to_date - from_date).to_i >= CPC_HISTORY_MAX_DAYS

        units = Array(units || cpc_units.where.not(state: "CAMPAIGN_STATE_ARCHIVED").to_a)
        total = 0
        product_map = raw_product_map

        units.each_slice(CPC_HISTORY_BATCH_SIZE) do |batch|
          request = {
            campaigns: batch.map(&:external_id), dateFrom: from_date.to_date.to_s,
            dateTo: to_date.to_date.to_s, groupBy: "DATE"
          }
          body = @report_runner.run(report_type: "cpc_product_history", endpoint: "/api/client/statistics",
            period_from: from_date, period_to: to_date, request_body: request) do
            @client.post("/api/client/statistics", request)
          end
          reports = cpc_history_reports(body, batch)
          unit_map = batch.index_by(&:external_id)
          rows = reports.flat_map do |external_id, csv|
            unit = unit_map[external_id.to_s]
            next [] unless unit
            CsvParser.cpc_product_history(csv).map do |item|
              item.merge(account_id: @account.id, ad_unit_id: unit.id,
                raw_ozon_product_id: product_map[item[:ozon_sku_id]], cost_model: "cpc_history",
                synced_at: Time.current, created_at: Time.current, updated_at: Time.current)
            end
          end
          upsert_sku_rows(rows)
          mark_cpc_history_report_imported(request, from_date: from_date, to_date: to_date, row_count: rows.size)
          total += rows.size
        end
        total
      end

      def sync_cpo_selected_stats(from_date:, to_date:)
        unit = cpo_selected_unit
        return 0 unless unit
        total = 0
        product_map = raw_product_map

        (from_date..to_date).each do |date|
          request = { from: "#{date}T00:00:00+03:00", to: "#{date}T23:59:59+03:00" }
          body = @report_runner.run(report_type: "cpo_selected_products", endpoint: "/api/client/statistic/products/generate",
            period_from: date, period_to: date, request_body: request) do
            @client.post("/api/client/statistic/products/generate", request)
          end
          rows = CsvParser.cpo_selected_products(body).flat_map do |item|
            cpo_selected_stat_rows(item, unit, date, product_map)
          end
          upsert_sku_rows(rows)
          total += rows.size
        end
        total
      end

      def sync_cpo_all_stats(from_date:, to_date:)
        unit = cpo_all_unit
        return 0 unless unit
        request = { "timeBounds.from" => "#{from_date}T00:00:00+03:00", "timeBounds.to" => "#{to_date}T23:59:59+03:00" }
        body = @report_runner.run(report_type: "cpo_all_products", endpoint: "/api/client/statistics/all_sku_promo/products/generate",
          period_from: from_date, period_to: to_date, request_body: request) do
          @client.get("/api/client/statistics/all_sku_promo/products/generate", request)
        end
        rows = CsvParser.cpo_all_daily(body).map do |item|
          item.merge(account_id: @account.id, ad_unit_id: unit.id, cost_model: "cpo_all_report", synced_at: Time.current,
            created_at: Time.current, updated_at: Time.current)
        end
        upsert_daily_rows(rows)
        rows.size
      end

      private

      def unit_row(item, synced_at)
        payment = item["PaymentType"].presence || item["paymentType"]
        object_type = item["advObjectType"].to_s
        unit_type = if object_type == "ALL_SKU_PROMO"
          "cpo_all"
        elsif object_type == "SEARCH_PROMO"
          "cpo_selected"
        else
          "cpc_campaign"
        end
        {
          account_id: @account.id, external_id: item["id"].to_s, unit_type: unit_type, title: item["title"],
          state: item["state"], billing_model: payment.to_s.downcase.presence, strategy: item["productAutopilotStrategy"],
          placement: Array(item["placement"]), daily_budget: money(item["dailyBudget"]),
          weekly_budget: money(item["weeklyBudget"]), from_date: item["fromDate"].presence,
          to_date: item["toDate"].presence, raw_json: item, synced_at: synced_at,
          created_at: synced_at, updated_at: synced_at
        }
      end

      def upsert_unit_products(unit, products, product_map, source:)
        synced_at = Time.current
        skus = products.filter_map { |item| (item["sku"] || item["sourceSku"]).to_s.presence }
        rows = products.filter_map do |item|
          sku = (item["sku"] || item["sourceSku"]).to_s.presence
          next unless sku
          {
            ad_unit_id: unit.id, ozon_sku_id: sku, raw_ozon_product_id: product_map[sku], title: item["title"],
            state: item["searchPromoStatus"] || item["state"], is_current: true,
            bid: source == "cpc" ? micro_money(item["bid"]) : decimal(item["bid"]),
            bid_price: decimal(item["bidPrice"]), target_cir: decimal(item["targetCir"]), price: decimal(item["price"]),
            views: integer(item["views"]), source_sku: item["sourceSku"]&.to_s, image_url: item["imageUrl"],
            raw_json: item.merge("source" => source), synced_at: synced_at, created_at: synced_at, updated_at: synced_at
          }
        end
        RawOzon::AdUnitProduct.upsert_all(rows, unique_by: :idx_raw_ozon_ad_unit_products_identity) if rows.any?
        stale = RawOzon::AdUnitProduct.where(ad_unit_id: unit.id, is_current: true)
        stale = stale.where.not(ozon_sku_id: skus) if skus.any?
        stale.update_all(is_current: false, removed_at: synced_at, updated_at: synced_at)
        rows.size
      end

      def build_cpc_sku_stat(item, unit, product_map)
        synced_at = Time.current
        sku = item["sku"].to_s
        {
          account_id: @account.id, ad_unit_id: unit.id, ozon_sku_id: sku, raw_ozon_product_id: product_map[sku],
          stat_date: Date.parse(item["date"]), cost_model: "cpc", impressions: integer(item["views"]),
          clicks: integer(item["clicks"]), cart_additions: integer(item["toCart"]), orders_count: integer(item["orders"]),
          model_orders_count: integer(item["modelOrders"]), ad_revenue: decimal(item["sales"]),
          model_revenue: decimal(item["modelSales"]), spend: decimal(item["expense"]), price: decimal(item["price"]),
          avg_cpc: decimal(item["avgCpc"]), ctr: decimal(item["ctr"]), drr: decimal(item["drr"]),
          date_added: item["dateAdded"].presence, raw_json: item, synced_at: synced_at,
          created_at: synced_at, updated_at: synced_at
        }
      end

      def cpo_selected_stat_rows(item, unit, date, product_map)
        %w[cpo combo].map do |model|
          synced_at = Time.current
          {
            account_id: @account.id, ad_unit_id: unit.id, ozon_sku_id: item[:ozon_sku_id],
            raw_ozon_product_id: product_map[item[:ozon_sku_id]], stat_date: date, cost_model: model,
            orders_count: item["#{model}_orders".to_sym], ad_revenue: item["#{model}_revenue".to_sym],
            spend: item["#{model}_spend".to_sym], price: item[:price], drr: model == "cpo" ? item[:drr] : nil,
            raw_json: item[:raw_json], synced_at: synced_at, created_at: synced_at, updated_at: synced_at
          }
        end
      end

      def upsert_daily_rows(rows)
        return if rows.empty?
        RawOzon::AdDailyStat.upsert_all(rows, unique_by: :idx_raw_ozon_ad_daily_stats_identity)
      end

      def upsert_sku_rows(rows)
        return if rows.empty?
        RawOzon::AdSkuDailyStat.upsert_all(rows, unique_by: :idx_raw_ozon_ad_sku_daily_stats_identity)
      end

      def raw_product_map
        @raw_product_map ||= RawOzon::Product.where(account_id: @account.id).each_with_object({}) do |product, map|
          sku = product.raw_json&.dig("sku").to_s.presence
          map[sku] = product.id if sku
        end
      end

      def cpc_history_reports(body, batch)
        return { batch.sole.external_id => body } unless body.start_with?("PK")

        Zip::File.open_buffer(StringIO.new(body)).each_with_object({}) do |entry, reports|
          next if entry.directory?
          external_id = File.basename(entry.name, File.extname(entry.name))
          reports[external_id] = entry.get_input_stream.read
        end
      end

      def mark_cpc_history_report_imported(request, from_date:, to_date:, row_count:)
        run = RawOzon::AdReportRun.where(account_id: @account.id, report_type: "cpc_product_history",
          period_from: from_date, period_to: to_date, state: "completed").order(:id).reverse_order.find do |candidate|
          Array(candidate.request_body["campaigns"]).map(&:to_s) == request.fetch(:campaigns).map(&:to_s)
        end
        return unless run

        run.update!(request_body: run.request_body.merge("imported_at" => Time.current.iso8601, "imported_rows" => row_count))
      end

      def cpc_units = RawOzon::AdUnit.where(account_id: @account.id, unit_type: "cpc_campaign")
      def cpo_selected_unit = RawOzon::AdUnit.find_by(account_id: @account.id, unit_type: "cpo_selected")
      def cpo_all_unit = RawOzon::AdUnit.find_by(account_id: @account.id, unit_type: "cpo_all")

      def response_array(response)
        %w[products list items].each do |key|
          value = response[key]
          return value if value.is_a?(Array)
        end
        response.values.find { |value| value.is_a?(Array) } || []
      end

      def decimal(value)
        value.is_a?(String) || value.is_a?(Numeric) ? value.to_d : nil
      end

      def integer(value)
        value.is_a?(String) || value.is_a?(Numeric) ? value.to_i : nil
      end
      def money(value) = micro_money(value)
      def micro_money(value) = value.presence && value.to_d / 1_000_000
    end
  end
end
