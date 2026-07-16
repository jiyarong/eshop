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
      offset = 0
      total = 0

      loop do
        response = @client.post(API_PATH, request_body(period_start, selected_period_end, offset))
        data = Array(response.dig("result", "data"))
        rows = data.filter_map do |item|
          build_row(item, period_start: period_start, period_end: period_end, synced_at: synced_at)
        end
        upsert_rows(rows) if rows.any?

        total += rows.size
        break if data.size < LIMIT

        offset += LIMIT
        sleep @rate_limit_sleep
      end

      { ok: total, fetched: total, skipped: false }
    rescue OzonClient::ApiError => e
      return skipped_result(e) if skippable_api_error?(e)

      raise
    end

    private

    def request_body(period_start, selected_period_end, offset)
      {
        date_from: period_start.iso8601,
        date_to: selected_period_end.iso8601,
        dimension: ["sku"],
        metrics: METRICS,
        filters: [],
        sort: [{ key: "revenue", order: "DESC" }],
        limit: LIMIT,
        offset: offset,
      }
    end

    def build_row(item, period_start:, period_end:, synced_at:)
      dimensions = Array(item["dimensions"])
      sku_dimension = dimensions.first || {}
      sku = sku_dimension["id"].presence
      return nil if sku.blank?

      metric_values = Array(item["metrics"])
      metrics = METRICS.each_with_index.to_h { |metric, index| [metric, metric_values[index]] }

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
        ordered_units: integer(metrics["ordered_units"]),
        revenue: decimal(metrics["revenue"]),
        returns_count: integer(metrics["returns"]),
        cancellations: integer(metrics["cancellations"]),
        raw_json: item,
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
  end
end
