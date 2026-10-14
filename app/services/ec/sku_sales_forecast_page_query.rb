module Ec
  # Read-only data set used by the SKU sales forecast workbench. Forecast
  # calculations stay in their existing services; this object only joins their
  # results with the historical facts shown on the page.
  class SkuSalesForecastPageQuery
    MAX_RANGE_DAYS = 366
    TRAINING_WEEKS = 4
    ACTIVE_DAYS = TRAINING_WEEKS * 7

    def initialize(sku:, from_date:, to_date:, as_of_date:, time_zone: Ec::Snapshot::TIME_ZONE)
      @sku = sku
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @as_of_date = as_of_date.to_date
      @time_zone = time_zone.is_a?(String) ? Time.find_zone!(time_zone) : time_zone

      raise ArgumentError, "to_date must be on or after from_date" if @to_date < @from_date
      raise ArgumentError, "as_of_date must be within the selected period" unless (@from_date..@to_date).cover?(@as_of_date)
      raise ArgumentError, "date range is too large" if (@to_date - @from_date).to_i >= MAX_RANGE_DAYS
    end

    def call
      {
        period: { from: @from_date, to: @to_date, as_of: @as_of_date },
        forecasts: forecasts,
        backtests: backtests,
        timeline: timeline
      }
    end

    private

    def forecasts
      @forecasts ||= {
        simple: simple_forecast,
        strict: strict_forecast,
        version_1: version_1_forecast,
        version_2: version_2_forecast
      }
    end

    def simple_forecast
      metrics = Ec::InventoryVelocityMetricsQuery.new(
        sku_codes: [ @sku.sku_code ],
        date_to: @as_of_date,
        time_zone: @time_zone
      ).call.fetch(@sku.sku_code, {})
      {
        daily_sales: decimal(metrics[:daily_sales_velocity]),
        training_days: nil,
        formula: "weighted_recent_sales"
      }
    end

    def strict_forecast
      result = ErpAI::DynamicDailySalesForecast.new(sku: @sku, date_to: @as_of_date - 1.day).call
      {
        daily_sales: decimal(result[:forecast_daily_sales]),
        training_days: result[:valid_days],
        formula: result.dig(:calculation, :path).to_s
      }
    rescue ArgumentError, ActiveRecord::RecordNotFound
      unavailable_forecast("strict")
    end

    def version_1_forecast
      result = version_1_service.forecast(as_of: @as_of_date, sku_code: @sku.sku_code).fetch(@sku.sku_code, {})
      normalize_forecast(result, "v1")
    rescue ArgumentError, ActiveRecord::RecordNotFound
      unavailable_forecast("v1")
    end

    def version_2_forecast
      result = version_2_service.forecast(as_of: @as_of_date, sku_code: @sku.sku_code).fetch(@sku.sku_code, {})
      normalize_forecast(result, "v2")
    rescue ArgumentError, ActiveRecord::RecordNotFound
      unavailable_forecast("v2")
    end

    def normalize_forecast(result, version)
      {
        daily_sales: decimal(result[:daily_sales]),
        training_days: result[:training_days],
        inventory_days: result[:inventory_days],
        formula: result[:formula].to_s,
        demand_state: result[:demand_state]&.to_s,
        version: version
      }
    end

    def unavailable_forecast(version)
      { daily_sales: nil, training_days: 0, inventory_days: 0, formula: version, version: version }
    end

    def backtests
      @backtests ||= begin
        first = backtest_for(version_1_service)
        second = backtest_for(version_2_service)
        first_rows = first.fetch(:predictions, [])
        second_rows = second.fetch(:predictions, [])
        keys = (first_rows + second_rows).map { |row| [ row[:as_of], row[:target_from], row[:target_to] ] }.uniq.sort

        keys.map do |key|
          {
            as_of: key[0],
            target_from: key[1],
            target_to: key[2],
            version_1: first_rows.find { |row| prediction_key(row) == key },
            version_2: second_rows.find { |row| prediction_key(row) == key }
          }
        end
      end
    rescue ArgumentError, ActiveRecord::RecordNotFound
      []
    end

    def backtest_for(service)
      service.backtest
    rescue ArgumentError, ActiveRecord::RecordNotFound
      { predictions: [] }
    end

    def version_1_service
      @version_1_service ||= Ec::SkuDailySalesForecast.new(
        sku_codes: [ @sku.sku_code ],
        from_date: @from_date,
        to_date: @to_date,
        time_zone: @time_zone,
        training_weeks: TRAINING_WEEKS,
        include_predictions: true
      )
    end

    def version_2_service
      @version_2_service ||= Ec::SkuDailySalesForecastV2.new(
        sku_codes: [ @sku.sku_code ],
        from_date: @from_date,
        to_date: @to_date,
        time_zone: @time_zone,
        training_weeks: TRAINING_WEEKS,
        active_days: ACTIVE_DAYS,
        include_predictions: true
      )
    end

    def prediction_key(row)
      [ row[:as_of], row[:target_from], row[:target_to] ]
    end

    def timeline
      sales = sales_by_date
      prices = prices_by_date
      ads = advertising_by_date
      previous_price = nil

      (@from_date..@to_date).map do |date|
        snapshot = snapshots_by_date[date]
        overview = snapshot&.data&.fetch(:overview, {}) || {}
        price = prices[date]
        price_change = price && previous_price ? price - previous_price : nil
        previous_price = price if price
        snapshot_sales = overview[:daily_sales]
        actual_sales = snapshot_sales.nil? ? sales[date] : snapshot_sales

        {
          date: date,
          actual_sales: decimal(actual_sales),
          actual_sales_source: snapshot_sales.nil? ? (sales.key?(date) ? "orders" : nil) : "snapshot",
          inventory: decimal(overview[:platform_stock] || overview[:inventory] || overview[:available_stock]),
          book_stock: decimal(overview[:book_stock]),
          out_of_stock: overview[:out_of_stock] == true || (overview[:platform_stock].present? && overview[:platform_stock].to_d <= 0),
          price: decimal(price),
          price_change: decimal(price_change),
          ad_enabled: ads.fetch(date, {}).fetch(:enabled, false),
          ad_spend: decimal(ads.fetch(date, {}).fetch(:spend, 0)),
          ad_campaign_count: ads.fetch(date, {}).fetch(:campaign_count, 0)
        }
      end
    end

    def snapshots
      @snapshots ||= @sku.snapshots
        .of_type(Ec::InventorySnapshot.snapshot_type)
        .between(@from_date, @to_date)
        .select(:sku_id, :snapshot_date, :content)
        .order(:snapshot_date)
        .to_a
    end

    def snapshots_by_date
      @snapshots_by_date ||= snapshots.index_by(&:snapshot_date)
    end

    def sales_by_date
      @sales_by_date ||= Ec::SkuDailySalesQuery.new(
        sku_codes: [ @sku.sku_code ],
        from_date: @from_date,
        to_date: @to_date,
        time_zone: @time_zone
      ).call.each_with_object({}) do |((date, _code), quantity), result|
        result[date.to_date] = quantity.to_d
      end
    end

    def prices_by_date
      @prices_by_date ||= begin
        date_sql = "DATE((ec_orders.ordered_at AT TIME ZONE 'UTC') AT TIME ZONE #{quoted_time_zone})"
        price_sql = <<~SQL.squish
          SUM(COALESCE(ec_order_items.buyer_paid_unit_price, ec_order_items.unit_price) * ec_order_items.quantity)
          / NULLIF(SUM(ec_order_items.quantity), 0)
        SQL
        order_items = Ec::OrderItem
          .joins(:order)
          .joins(order_item_sku_product_join_sql)
          .where(ec_sku_products: { sku_code: @sku.sku_code })
          .where.not(ec_orders: { order_status: %w[cancelled returned] })
          .where(ec_orders: { ordered_at: user_date_range })
          .where("COALESCE(ec_order_items.buyer_paid_unit_price, ec_order_items.unit_price) IS NOT NULL")

        order_items
          .group(Arel.sql(date_sql))
          .pluck(Arel.sql(date_sql), Arel.sql(price_sql))
          .to_h { |date, price| [ date.to_date, price&.to_d ] }
      end
    end

    def advertising_by_date
      @advertising_by_date ||= begin
        result = (@from_date..@to_date).index_with { { spend: 0.to_d, enabled: false, campaign_count: 0 } }
        wb_products = @sku.sku_products.active.where(platform: "wb").to_a
        wb_ids = wb_products.filter_map { |product| Integer(product.product_id, exception: false) }
        if wb_ids.any?
          campaigns = RawWb::AdvCampaign
            .joins(:products)
            .where(raw_wb_adv_campaign_products: { nm_id: wb_ids, is_current: true })
            .distinct
            .to_a
          stats = RawWb::AdvProductDailyStat.all_apps
            .where(campaign_id: campaigns.map(&:id), nm_id: wb_ids, stat_date: @from_date..@to_date)
          stats.group(:stat_date).sum(:spend).each { |date, amount| result[date][:spend] += amount.to_d }
          campaigns.each do |campaign|
            result.each_key { |date| result[date][:enabled] = true if campaign_active_on?(campaign, date) }
          end
          result.each_value { |row| row[:campaign_count] += campaigns.size }
        end

        ozon_products = @sku.sku_products.active.where(platform: "ozon").to_a
        ozon_ids = ozon_products.map { |product| product.platform_sku_id.to_s }.reject(&:blank?)
        if ozon_ids.any?
          units = RawOzon::AdUnit
            .joins(:products)
            .where(raw_ozon_ad_unit_products: { ozon_sku_id: ozon_ids, is_current: true })
            .distinct
            .to_a
          stats = RawOzon::AdSkuDailyStat.where(
            ad_unit_id: units.map(&:id), ozon_sku_id: ozon_ids, stat_date: @from_date..@to_date
          )
          stats.group(:stat_date).sum(:spend).each { |date, amount| result[date][:spend] += amount.to_d }
          units.each do |unit|
            result.each_key { |date| result[date][:enabled] = true if unit_active_on?(unit, date) }
          end
          result.each_value { |row| row[:campaign_count] += units.size }
        end

        result
      end
    end

    def campaign_active_on?(campaign, date)
      return false if campaign.source_started_at && campaign.source_started_at.to_date > date
      return false if campaign.source_deleted_at && campaign.source_deleted_at.to_date < date

      campaign.status.to_i == 9
    end

    def unit_active_on?(unit, date)
      unit.state.to_s == "CAMPAIGN_STATE_RUNNING" &&
        (unit.from_date.nil? || unit.from_date <= date) && (unit.to_date.nil? || unit.to_date >= date)
    end

    def order_item_sku_product_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_order_items.store_id
         AND ec_sku_products.platform = ec_order_items.platform
         AND ((ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
           OR (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id))
      SQL
    end

    def quoted_time_zone
      ActiveRecord::Base.connection.quote(@time_zone.tzinfo.name)
    end

    def user_date_range
      @time_zone.local(@from_date.year, @from_date.month, @from_date.day).beginning_of_day..
        @time_zone.local(@to_date.year, @to_date.month, @to_date.day).end_of_day
    end

    def decimal(value)
      value.nil? ? nil : value.to_d.round(4)
    end
  end
end
