module RawOzon
  class SalesFunnelPeriodSync
    API_PATH = "/v1/analytics/data".freeze
    LIMIT = 1000
    RATE_LIMIT_SLEEP = 60
    METRICS = %w[
      hits_view
      hits_view_search
      hits_view_pdp
      session_view
      session_view_search
      session_view_pdp
      hits_tocart
      hits_tocart_search
      hits_tocart_pdp
      conv_tocart
      ordered_units
      revenue
      returns
      cancellations
    ].freeze
    SUPPLEMENTAL_METRICS = %w[
      conv_tocart_search
      conv_tocart_pdp
      delivered_units
      position_category
    ].freeze

    def self.run_current_week
      today = Date.current
      period_start = today.beginning_of_week(:monday)
      run_period(period_start: period_start, period_end: period_start + 6.days, selected_period_end: today)
    end

    def self.run_completed_week(weeks_ago: 2)
      period_start = Date.current.beginning_of_week(:monday) - weeks_ago.weeks
      run_period(period_start: period_start, period_end: period_start + 6.days)
    end

    def self.run_period(period_start:, period_end:, selected_period_end: nil)
      stores = Ec::Store.where(platform: "ozon", is_active: true)
      raise ArgumentError, "No active Ozon stores found in ec_stores" if stores.none?

      stores.each_with_object({}) do |store, results|
        account = store.raw_ozon_account
        raise "Ec::Store##{store.id} (#{store.store_name}) has no linked Ozon account" unless account

        results[store.id] = new(account).sync_period(
          period_start: period_start.to_date,
          period_end: period_end.to_date,
          selected_period_end: selected_period_end&.to_date
        )
      end
    end

    def initialize(account, client: nil, rate_limit_sleep: RATE_LIMIT_SLEEP)
      @account = account
      @client = client || OzonClient.new(account.client_id, account.api_key)
      @rate_limit_sleep = rate_limit_sleep
    end

    def sync_period(period_start:, period_end:, selected_period_end: nil)
      period_start = period_start.to_date
      period_end = period_end.to_date
      selected_period_end = selected_period_end&.to_date || period_end
      raise ArgumentError, "period_end must be on or after period_start" if period_end < period_start
      raise ArgumentError, "selected_period_end must be on or after period_start" if selected_period_end < period_start
      raise ArgumentError, "selected_period_end must be on or before period_end" if selected_period_end > period_end

      synced_at = Time.current
      metric_rows = fetch_metric_rows(period_start, selected_period_end)
      rows = metric_rows.values.filter_map do |entry|
        build_row(entry, period_start: period_start, period_end: period_end, synced_at: synced_at)
      end
      upsert_rows(rows) if rows.any?
      { ok: rows.size, fetched: rows.size, skipped: false }
    rescue OzonClient::ApiError => e
      return skipped_result(e) if skippable_api_error?(e)

      raise
    end

    private

    def fetch_metric_rows(period_start, selected_period_end)
      [METRICS, SUPPLEMENTAL_METRICS].each_with_index.with_object({}) do |(metrics, metric_index), rows_by_sku|
        sleep @rate_limit_sleep if metric_index.positive?
        offset = 0
        loop do
          response = @client.post(API_PATH, request_body(period_start, selected_period_end, offset, metrics))
          data = Array(response.dig("result", "data"))
          merge_metric_rows(rows_by_sku, data, metrics)
          break if data.size < LIMIT

          offset += LIMIT
          sleep @rate_limit_sleep
        end
      end
    end

    def request_body(period_start, selected_period_end, offset, metrics)
      {
        date_from: period_start.iso8601,
        date_to: selected_period_end.iso8601,
        dimension: ["sku"],
        metrics: metrics,
        filters: [],
        sort: [{ key: "revenue", order: "DESC" }],
        limit: LIMIT,
        offset: offset,
      }
    end

    def merge_metric_rows(rows_by_sku, data, metrics)
      data.each do |item|
        dimension = Array(item["dimensions"]).first || {}
        sku = dimension["id"].presence
        next if sku.blank?

        entry = (rows_by_sku[sku.to_s] ||= { "dimension" => dimension, "metrics" => {}, "raw_rows" => {} })
        entry["metrics"].merge!(metrics.zip(Array(item["metrics"])).to_h)
        entry["raw_rows"][metrics.join(",")] = item
      end
    end

    def build_row(entry, period_start:, period_end:, synced_at:)
      sku_dimension = entry["dimension"]
      sku = sku_dimension["id"].presence
      return nil if sku.blank?
      metrics = entry["metrics"]

      {
        account_id: @account.id,
        period_start: period_start,
        period_end: period_end,
        sku: sku.to_i,
        product_name: sku_dimension["name"],
        hits_view: integer(metrics["hits_view"]),
        hits_view_search: integer(metrics["hits_view_search"]),
        hits_view_pdp: integer(metrics["hits_view_pdp"]),
        session_view: integer(metrics["session_view"]),
        session_view_search: integer(metrics["session_view_search"]),
        session_view_pdp: integer(metrics["session_view_pdp"]),
        hits_tocart: integer(metrics["hits_tocart"]),
        hits_tocart_search: integer(metrics["hits_tocart_search"]),
        hits_tocart_pdp: integer(metrics["hits_tocart_pdp"]),
        conv_tocart: decimal(metrics["conv_tocart"]),
        conv_tocart_search: optional_decimal(metrics["conv_tocart_search"]),
        conv_tocart_pdp: optional_decimal(metrics["conv_tocart_pdp"]),
        ordered_units: integer(metrics["ordered_units"]),
        delivered_units: integer(metrics["delivered_units"]),
        revenue: decimal(metrics["revenue"]),
        returns_count: integer(metrics["returns"]),
        cancellations: integer(metrics["cancellations"]),
        position_category: optional_decimal(metrics["position_category"]),
        raw_json: { "dimensions" => [sku_dimension], "metric_values" => metrics, "source_rows" => entry["raw_rows"] },
        synced_at: synced_at,
        created_at: synced_at,
        updated_at: synced_at,
      }
    end

    def upsert_rows(rows)
      RawOzon::SalesFunnelPeriod.upsert_all(
        rows,
        unique_by: :idx_raw_ozon_sales_funnel_period_unique,
        update_only: update_columns
      )
    end

    def update_columns
      @update_columns ||= RawOzon::SalesFunnelPeriod.column_names.map(&:to_sym) -
        %i[id account_id period_start period_end sku created_at updated_at]
    end

    def skippable_api_error?(error)
      message = error.message.downcase
      message.include?("premium") ||
        message.include?("subscription") ||
        message.include?("not available") ||
        message.include?("unavailable") ||
        message.include?("access denied") ||
        message.include?("403") ||
        (message.include?("400") && message.include?("metric"))
    end

    def skipped_result(error)
      {
        ok: 0,
        fetched: 0,
        skipped: true,
        error: error.message,
      }
    end

    def integer(value)
      value.to_i
    end

    def decimal(value)
      value.to_f
    end

    def optional_decimal(value)
      value.to_f unless value.nil?
    end
  end
end
