module Ec
  # Calculates a daily SKU sales forecast from local daily snapshots and evaluates
  # it with rolling-origin backtests. This service is intentionally independent
  # from the existing report and AI forecast services.
  class SkuDailySalesForecast
    DEFAULT_TRAINING_WEEKS = 2
    DEFAULT_HORIZON_DAYS = 7
    DEFAULT_STEP_DAYS = 7
    DEFAULT_TOLERANCE = BigDecimal("0.4")
    DEFAULT_TARGET_ACCURACY = BigDecimal("0.8")
    DEFAULT_FORMULA = :weighted_mean
    DEFAULT_RECENCY_DECAY = BigDecimal("0.2")
    DEFAULT_VELOCITY_WEIGHT = BigDecimal("0")
    FORMULAS = %i[weighted_mean ewma adaptive].freeze
    MAX_TRAINING_WEEKS = 52

    def initialize(sku: nil, skus: nil, sku_codes: nil, from_date: nil, to_date: nil,
      training_weeks: DEFAULT_TRAINING_WEEKS,
      horizon_days: DEFAULT_HORIZON_DAYS, step_days: DEFAULT_STEP_DAYS,
      tolerance: DEFAULT_TOLERANCE, target_accuracy: DEFAULT_TARGET_ACCURACY,
      formula: DEFAULT_FORMULA, recency_decay: DEFAULT_RECENCY_DECAY,
      velocity_weight: DEFAULT_VELOCITY_WEIGHT,
      time_zone: nil, include_predictions: true)
      requested_skus = sku_codes || skus || (sku ? [ sku ] : nil)
      @sku_filter_requested = !requested_skus.nil?
      @requested_sku_codes = Array(requested_skus).filter_map { |code| sku_code_for(code) }.uniq
      snapshot_scope = Ec::Snapshot.of_type(Ec::InventorySnapshot.snapshot_type)
      @from_date = (from_date || snapshot_scope.minimum(:snapshot_date))&.to_date
      @to_date = (to_date || snapshot_scope.maximum(:snapshot_date))&.to_date
      @training_weeks = positive_integer(training_weeks, :training_weeks, max: MAX_TRAINING_WEEKS)
      @horizon_days = positive_integer(horizon_days, :horizon_days)
      @step_days = positive_integer(step_days, :step_days)
      @tolerance = decimal_between(tolerance, :tolerance, min: 0, max: 1)
      @target_accuracy = decimal_between(target_accuracy, :target_accuracy, min: 0, max: 1)
      @formula = normalize_formula(formula)
      @recency_decay = decimal_between(recency_decay, :recency_decay, min: 0, max: 1)
      @velocity_weight = decimal_between(velocity_weight, :velocity_weight, min: 0, max: 1)
      @time_zone = time_zone.is_a?(String) ? Time.find_zone!(time_zone) :
        (time_zone || Time.find_zone!(Ec::Snapshot::TIME_ZONE))
      @include_predictions = include_predictions
      raise ArgumentError, "local snapshot dates are required" unless @from_date && @to_date
      raise ArgumentError, "to_date must be on or after from_date" if @to_date < @from_date
    end

    # Runs a rolling-origin evaluation. Each prediction only sees dates through
    # its as_of date; the following horizon is used as the comparison target.
    def call
      backtest
    end

    def backtest
      series = daily_series
      eligible_codes = series.filter_map do |sku_code, rows|
        sku_code if rows.sum { |row| row[:sales] } > 0
      end
      folds = fold_dates
      predictions = build_predictions(series, eligible_codes, folds)

      sku_summaries = summarize_skus(predictions, eligible_codes, folds.size)
      overall = summarize_predictions(predictions).merge(
        sku_meets_target_count: sku_summaries.count { |sku| sku[:meets_target] },
        sku_accuracy_rate: ratio(sku_summaries.count { |sku| sku[:meets_target] }, sku_summaries.size),
        observed_prediction_coverage_rate: ratio(predictions.size, eligible_codes.size * folds.size)
      )
      result = {
        period: { from: @from_date, to: @to_date },
        parameters: parameters,
        eligible_sku_count: eligible_codes.size,
        fold_count: folds.size,
        prediction_count: predictions.size,
        overall: overall,
        skus: sku_summaries
      }
      result[:predictions] = predictions if @include_predictions
      result
    end

    # Returns the forecast at a chosen as_of date. With no sku_code, returns all
    # locally known SKUs that have at least one observed sale in the loaded range.
    def forecast(as_of: @to_date, sku_code: nil)
      as_of = as_of.to_date
      series = daily_series
      selected_codes = sku_code ? [ normalize_code(sku_code) ] : series.keys
      selected_codes.each_with_object({}) do |code, result|
        rows = series[code]
        next unless rows

        training_rows = rows.select { |row| row[:date] <= as_of && row[:date] > as_of - training_days }
        result[code] = forecast_from_rows(training_rows, as_of: as_of)
      end
    end

    private

    def parameters
      {
        training_weeks: @training_weeks,
        training_days: training_days,
        horizon_days: @horizon_days,
        step_days: @step_days,
        tolerance: @tolerance,
        target_accuracy: @target_accuracy,
        formula: @formula.to_s,
        recency_decay: @recency_decay,
        velocity_weight: @velocity_weight,
        formula_description: formula_description
      }
    end

    def sku_records
      @sku_records ||= begin
        scope = Ec::Sku.select(:id, :sku_code)
        scope = scope.where(sku_code: @requested_sku_codes) if @sku_filter_requested
        scope.to_a
      end
    end

    def sku_codes
      @sku_codes ||= sku_records.map(&:sku_code).map(&:to_s).map(&:upcase).uniq
    end

    def daily_series
      @daily_series ||= begin
        return {} if sku_records.empty?

        snapshots = Ec::Snapshot
          .of_type(Ec::InventorySnapshot.snapshot_type)
          .where(sku_id: sku_records.map(&:id))
          .between(@from_date, @to_date)
          .select(:sku_id, :snapshot_date, :content)
          .order(:snapshot_date)
          .to_a
        snapshots_by_key = snapshots.index_by { |snapshot| [ snapshot.sku_id, snapshot.snapshot_date ] }
        sales_by_key = Ec::SkuDailySalesQuery.new(
          sku_codes: sku_codes,
          from_date: @from_date,
          to_date: @to_date,
          time_zone: @time_zone
        ).call
        records_by_code = sku_records.index_by { |sku| sku.sku_code.to_s.upcase }

        sku_codes.index_with do |code|
          sku_id = records_by_code.fetch(code).id
          (@from_date..@to_date).map do |date|
            snapshot = snapshots_by_key[[ sku_id, date ]]
            overview = snapshot ? (snapshot.data.fetch(:overview, {}) || {}) : {}
            snapshot_sales = overview[:daily_sales]
            sales_key = [ date, code ]
            sales_present = sales_by_key.key?(sales_key)
            sales = snapshot_sales.nil? ? sales_by_key.fetch(sales_key, 0) : snapshot_sales
            inventory = inventory_value(overview)

            {
              date: date,
              sales: sales.to_d,
              inventory: inventory,
              daily_sales_velocity: decimal_value(overview[:daily_sales_velocity]),
              marketing_stage: overview[:marketing_stage].to_s,
              marketing_grade: overview[:marketing_grade].to_s,
              out_of_stock: out_of_stock?(overview, inventory),
              observed: snapshot.present? || sales_present
            }
          end
        end
      end
    end

    def fold_dates
      last_as_of = @to_date - @horizon_days.days
      first_as_of = @from_date + training_days - 1.day
      return [] if last_as_of < first_as_of

      dates = []
      as_of = first_as_of
      while as_of <= last_as_of
        dates << as_of
        as_of += @step_days.days
      end
      dates
    end

    def build_predictions(series, eligible_codes, folds)
      folds.flat_map do |as_of|
        eligible_codes.filter_map do |sku_code|
          rows = series.fetch(sku_code)
          actual_rows = rows.select { |row| row[:date] > as_of && row[:date] <= as_of + @horizon_days.days }
          next unless actual_rows.size == @horizon_days && actual_rows.all? { |row| row[:observed] }

          forecast = forecast_from_rows(
            rows.select { |row| row[:date] <= as_of && row[:date] > as_of - training_days },
            as_of: as_of
          )
          actual_units = actual_rows.sum { |row| row[:sales] }
          predicted_units = forecast.fetch(:daily_sales) * actual_rows.size

          {
            sku_code: sku_code,
            as_of: as_of,
            target_from: actual_rows.first.fetch(:date),
            target_to: actual_rows.last.fetch(:date),
            training_days: forecast.fetch(:training_days),
            inventory_days: forecast.fetch(:inventory_days),
            formula: forecast.fetch(:formula, @formula).to_s,
            historical_daily_sales_velocity: forecast[:daily_sales_velocity],
            predicted_daily_sales: forecast.fetch(:daily_sales),
            predicted_units: predicted_units,
            actual_units: actual_units,
            actual_daily_sales: actual_units / actual_rows.size,
            absolute_error: (predicted_units - actual_units).abs,
            relative_error: relative_error(predicted_units, actual_units),
            accurate: accurate?(predicted_units, actual_units)
          }
        end
      end
    end

    def forecast_from_rows(rows, as_of:)
      usable_rows = rows.select { |row| row[:observed] }.reject { |row| row[:out_of_stock] }
      return empty_forecast if usable_rows.empty?

      formula = selected_formula(usable_rows)
      daily_sales = case formula
      when :weighted_mean
        weighted_average(usable_rows, as_of: as_of)
      when :ewma
        exponential_average(usable_rows, as_of: as_of)
      when :recent_mean
        average(usable_rows.last([ usable_rows.size, 7 ].min).map { |row| row.fetch(:sales).to_d })
      else
        raise ArgumentError, "unsupported forecast formula: #{formula}"
      end
      return empty_forecast if daily_sales.nil?

      velocity = average(usable_rows.filter_map { |row| row[:daily_sales_velocity] })
      if @velocity_weight.positive? && velocity
        daily_sales = (daily_sales * (1 - @velocity_weight)) + (velocity * @velocity_weight)
      end

      {
        daily_sales: daily_sales,
        training_days: usable_rows.size,
        inventory_days: usable_rows.count { |row| row[:inventory] },
        formula: formula,
        daily_sales_velocity: velocity
      }
    end

    def selected_formula(rows)
      return @formula unless @formula == :adaptive

      stage = rows.reverse.find { |row| row[:marketing_stage].present? }&.fetch(:marketing_stage)
      case stage
      when "grw"
        :weighted_mean
      when "mat"
        :ewma
      when "new", "clr"
        :ewma
      else
        :recent_mean
      end
    end

    def weighted_average(rows, as_of:)
      weighted_rows = rows.filter_map do |row|
        age_days = (as_of - row.fetch(:date)).to_i
        next if age_days.negative? || age_days >= training_days

        recency = (training_days - age_days).to_d / training_days
        availability = inventory_availability(row)
        { sales: row.fetch(:sales).to_d, weight: recency * availability }
      end.select { |row| row[:weight].positive? }
      return if weighted_rows.empty?

      total_weight = weighted_rows.sum(BigDecimal("0")) { |row| row.fetch(:weight) }
      weighted_rows.sum(BigDecimal("0")) { |row| row.fetch(:sales) * row.fetch(:weight) } / total_weight
    end

    def exponential_average(rows, as_of:)
      filtered_rows = rows.select do |row|
        age_days = (as_of - row.fetch(:date)).to_i
        age_days >= 0 && age_days < training_days
      end.sort_by { |row| row.fetch(:date) }
      return if filtered_rows.empty?
      return average(filtered_rows.map { |row| row.fetch(:sales).to_d }) if @recency_decay.zero?

      filtered_rows.drop(1).reduce(filtered_rows.first.fetch(:sales).to_d) do |value, row|
        (@recency_decay * row.fetch(:sales).to_d) + ((1 - @recency_decay) * value)
      end
    end

    def inventory_availability(row)
      inventory = row[:inventory]
      return BigDecimal("1") unless inventory
      return BigDecimal("0") unless inventory.positive?

      denominator = inventory + row.fetch(:sales).to_d
      return BigDecimal("1") unless denominator.positive?

      inventory / denominator
    end

    def inventory_value(overview)
      value = overview[:inventory] || overview[:platform_stock] || overview[:available_stock] || overview[:book_stock]
      decimal_value(value)
    end

    def decimal_value(value)
      value.nil? ? nil : value.to_d
    end

    def out_of_stock?(overview, inventory)
      overview[:out_of_stock] == true || (inventory && inventory <= 0)
    end

    def empty_forecast
      { daily_sales: BigDecimal("0"), training_days: 0, inventory_days: 0 }
    end

    def summarize_predictions(predictions)
      positive_actual = predictions.select { |prediction| prediction[:actual_units].positive? }
      actual_units = predictions.sum { |prediction| prediction[:actual_units] }
      predicted_units = predictions.sum { |prediction| prediction[:predicted_units] }
      accurate_count = predictions.count { |prediction| prediction[:accurate] }
      positive_accurate_count = positive_actual.count { |prediction| prediction[:accurate] }
      absolute_error = predictions.sum { |prediction| prediction[:absolute_error] }

      {
        accurate_count: accurate_count,
        accuracy_rate: ratio(accurate_count, predictions.size),
        positive_actual_accuracy_rate: ratio(positive_accurate_count, positive_actual.size),
        mape: average(positive_actual.filter_map { |prediction| prediction[:relative_error] }),
        wape: actual_units.positive? ? (absolute_error / actual_units).round(4) : nil,
        bias: actual_units.positive? ? ((predicted_units - actual_units) / actual_units).round(4) : nil,
        actual_units: actual_units,
        predicted_units: predicted_units,
        zero_actual_prediction_units: predictions.reject { |prediction| prediction[:actual_units].positive? }
          .sum { |prediction| prediction[:predicted_units] },
        meets_target: ratio(accurate_count, predictions.size).to_d >= @target_accuracy
      }
    end

    def summarize_skus(predictions, eligible_codes, fold_count)
      predictions_by_sku = predictions.group_by { |prediction| prediction[:sku_code] }
      eligible_codes.map do |sku_code|
        rows = predictions_by_sku.fetch(sku_code, [])
        actual_units = rows.sum { |prediction| prediction[:actual_units] }
        predicted_units = rows.sum { |prediction| prediction[:predicted_units] }
        accuracy_rate = ratio(rows.count { |prediction| prediction[:accurate] }, rows.size)
        {
          sku_code: sku_code,
          fold_count: rows.size,
          coverage_rate: ratio(rows.size, fold_count),
          accurate_count: rows.count { |prediction| prediction[:accurate] },
          accuracy_rate: accuracy_rate,
          actual_units: actual_units,
          predicted_units: predicted_units,
          wape: actual_units.positive? ? (rows.sum { |prediction| prediction[:absolute_error] } / actual_units).round(4) : nil,
          meets_target: rows.any? && accuracy_rate.to_d >= @target_accuracy
        }
      end
    end

    def relative_error(predicted, actual)
      return nil unless actual.positive?

      ((predicted - actual).abs / actual).round(4)
    end

    def accurate?(predicted, actual)
      return predicted.abs <= BigDecimal("1") unless actual.positive?

      ((predicted - actual).abs / actual) <= @tolerance
    end

    def average(values)
      return if values.empty?

      (values.sum(BigDecimal("0")) / values.size).round(4)
    end

    def ratio(numerator, denominator)
      return BigDecimal("0") if denominator.to_i.zero?

      (numerator.to_d / denominator).round(4)
    end

    def training_days
      @training_days ||= @training_weeks * 7
    end

    def normalize_code(code)
      code.to_s.strip.upcase
    end

    def normalize_formula(formula)
      value = formula.to_s.strip.downcase.to_sym
      return value if FORMULAS.include?(value)

      raise ArgumentError, "formula must be one of #{FORMULAS.join(", ")}"
    end

    def formula_description
      {
        weighted_mean: "recency and inventory availability weighted sales",
        ewma: "exponentially weighted sales with configurable recency decay",
        adaptive: "marketing stage selected weighted, exponential, or recent mean sales"
      }.fetch(@formula)
    end

    def sku_code_for(value)
      code = value.respond_to?(:sku_code) ? value.sku_code : value
      normalize_code(code).presence
    end

    def positive_integer(value, name, max: nil)
      integer = Integer(value)
      valid = integer.positive? && (max.nil? || integer <= max)
      raise ArgumentError, "#{name} must be a positive integer#{max ? " no greater than #{max}" : ""}" unless valid

      integer
    rescue TypeError, ArgumentError
      raise ArgumentError, "#{name} must be a positive integer#{max ? " no greater than #{max}" : ""}"
    end

    def decimal_between(value, name, min:, max:)
      decimal = value.to_d
      raise ArgumentError, "#{name} must be between #{min} and #{max}" unless decimal.between?(min.to_d, max.to_d)

      decimal
    rescue NoMethodError, ArgumentError
      raise ArgumentError, "#{name} must be between #{min} and #{max}"
    end
  end
end
