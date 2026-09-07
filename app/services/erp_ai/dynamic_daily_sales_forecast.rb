module ErpAI
  class DynamicDailySalesForecast
    WINDOW_DAYS = 30
    SHORT_WINDOW_DAYS = 7
    MEDIUM_WINDOW_DAYS = 15
    TREND_DAYS = 15

    def initialize(sku: nil, skus: nil, date_to: Ec::Snapshot.current_date - 1)
      @skus = Array(skus || sku).compact
      raise ArgumentError, "sku or skus is required" if @skus.empty?
      @date_to = date_to.to_date
      @date_from = @date_to - (WINDOW_DAYS - 1).days
    end

    def call
      return call_many if @skus.size > 1

      call_one(@skus.first)
    end

    private

    def call_many
      snapshots_by_sku = snapshots.group_by(&:sku_id)
      sales_by_date = fallback_sales_by_date
      @skus.index_with do |sku|
        call_one(sku, snapshot_rows: snapshots_by_sku.fetch(sku.id, []), sales_by_date: sales_by_date)
      end
    end

    def call_one(sku, snapshot_rows: nil, sales_by_date: nil)
      @sku = sku
      @current_snapshots = snapshot_rows
      @current_sales_by_date = sales_by_date
      timeline = effective_timeline
      calculation = calculate(timeline.map { |day| day.fetch(:sales) })

      {
        sku: @sku.sku_code,
        marketing_stage: @sku.current_marketing_state&.stage&.upcase,
        forecast_daily_sales: decimal(calculation.fetch(:forecast)),
        snapshot_period: { from: @date_from, to: @date_to },
        snapshot_days: snapshots.size,
        valid_days: timeline.size,
        stockout_days: snapshots.count { |snapshot| out_of_stock?(snapshot) },
        calculation: calculation.except(:forecast).transform_values { |value| decimal(value) }
      }
    ensure
      @current_snapshots = nil
      @current_sales_by_date = nil
    end

    def snapshots
      return @current_snapshots if @current_snapshots

      @snapshots ||= Ec::Snapshot
        .of_type(Ec::InventorySnapshot.snapshot_type)
        .where(sku_id: @skus.map(&:id))
        .between(@date_from, @date_to)
        .order(:snapshot_date)
        .to_a
    end

    def effective_timeline
      sales_by_date = fallback_sales_by_date

      snapshots.filter_map do |snapshot|
        next if out_of_stock?(snapshot)

        overview = snapshot.data.fetch(:overview, {})
        sales = if overview.key?(:daily_sales)
          overview[:daily_sales]
        else
          sales_by_date.fetch([ snapshot.snapshot_date, @sku.sku_code ], 0)
        end

        { date: snapshot.snapshot_date, sales: sales.to_d }
      end
    end

    def fallback_sales_by_date
      return @current_sales_by_date if @current_sales_by_date

      current = @current_snapshots || snapshots
      return {} if current.all? { |snapshot| snapshot.data.fetch(:overview, {}).key?(:daily_sales) }

      Ec::SkuDailySalesQuery.new(
        sku_codes: @skus.map(&:sku_code),
        from_date: @date_from,
        to_date: @date_to,
        time_zone: snapshot_time_zone
      ).call
    end

    def out_of_stock?(snapshot)
      snapshot.data.dig(:overview, :out_of_stock) == true
    end

    def calculate(valid_sales)
      return empty_calculation if valid_sales.empty?

      if valid_sales.size < SHORT_WINDOW_DAYS
        return { forecast: average(valid_sales), path: :cold_start }
      end

      s7 = average(valid_sales.last(SHORT_WINDOW_DAYS))
      s15 = average(valid_sales.last(MEDIUM_WINDOW_DAYS))
      s30 = average(valid_sales.last(WINDOW_DAYS))
      past_sales = valid_sales[0...-SHORT_WINDOW_DAYS]

      if past_sales.empty?
        return { forecast: s7, path: :cold_start, s7: s7, s15: s15, s30: s30 }
      end

      historical_s7 = average(past_sales.last(SHORT_WINDOW_DAYS))
      slope = (s7 - historical_s7) / SHORT_WINDOW_DAYS
      base = { s7: s7, s15: s15, s30: s30, historical_s7: historical_s7, slope: slope }

      if clearance_stage? && slope.positive?
        return base.merge(forecast: average([ s7, s15, s30 ]), path: :stable)
      end

      if slope.positive? && s7 > s15
        forecast = [ s7 + (slope * TREND_DAYS), s7 * BigDecimal("1.5") ].min
        base.merge(forecast: forecast, path: :rising)
      elsif slope.negative? && s7 < s15
        forecast = [ s7 + (slope * TREND_DAYS), s30 * BigDecimal("0.5") ].max
        base.merge(forecast: forecast, path: :declining)
      else
        base.merge(forecast: average([ s7, s15, s30 ]), path: :stable)
      end
    end

    def empty_calculation
      { forecast: BigDecimal("0"), path: :no_valid_days }
    end

    def average(values)
      values.sum(BigDecimal("0")) / values.size
    end

    def clearance_stage?
      @sku.current_marketing_state&.stage == "clr"
    end

    def snapshot_time_zone
      @snapshot_time_zone ||= Time.find_zone!(Ec::Snapshot::TIME_ZONE)
    end

    def decimal(value)
      value.is_a?(Numeric) ? value.round(4).to_f : value
    end
  end
end
