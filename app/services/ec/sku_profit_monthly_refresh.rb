module Ec
  # Once a month (the 1st), every active SKU gets an automatic profit version for that month: all the standard
  # scenarios, built from nothing but
  #   - the SKU file (cost, freight, duty, dimensions) as of the 1st,
  #   - the last four full weeks of platform data (SkuProfitActualInputs: logistics, return rate, storage,
  #     advertising, acquiring, handover and cross-docking fees, the price the buyer paid),
  #   - the official commission rate (SkuOfficialCommissionRate: only when it is unambiguous),
  #   - the price the scenario actually sold at over those weeks, when at least SkuProfitPriceFromActuals::MIN_UNITS
  #     units were sold in it, and
  #   - the fixed formulas and defaults of SkuProfitCalculator.
  # Nothing is carried over from an earlier version and nobody types anything: what these sources cannot give stays
  # empty and the scenario reports that it cannot be calculated. Freight comes from the real bills when the scenario
  # has them and gives a valid result, otherwise from the fixed formula (the scenario's logistics_mode says which).
  #
  # The version is automatic (Ec::SkuProfitVersion): published for its month, read-only, never current. Running again
  # for the same month builds the same version from the same data and replaces it, so the job is idempotent and a
  # month can be rebuilt. Manual versions are never touched.
  class SkuProfitMonthlyRefresh
    DEFAULT_TIME_ZONE = "Asia/Shanghai".freeze
    IDENTITY_KEYS = Ec::SkuProfitStandardContexts::IDENTITY_KEYS

    def self.run(**options)
      new(**options).call
    end

    # month_start: the first day of the month the version covers (default: this month, in the business time zone).
    # today: the date the four-week window is counted back from.
    def initialize(month_start: nil, today: nil, time_zone: DEFAULT_TIME_ZONE, dry_run: false, sku_scope: Ec::Sku.where(is_active: true))
      @time_zone = ActiveSupport::TimeZone[time_zone.to_s] || ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
      @today = (today || @time_zone.today).to_date
      @month_start = (month_start || @today).to_date.beginning_of_month
      @dry_run = dry_run
      @sku_scope = sku_scope
    end

    def call
      summary = {
        mode: dry_run ? "dry_run" : "apply",
        month_start: month_start.iso8601,
        data_from: data_from.iso8601,
        data_to: data_to.iso8601,
        built: [], failures: []
      }
      sku_scope.find_each do |sku|
        summary[:built] << build_for(sku)
      rescue StandardError => error
        summary[:failures] << { sku_code: sku.sku_code, error: "#{error.class}: #{error.message}" }
      end
      summary[:ok] = summary[:failures].empty?
      summary
    end

    private

    attr_reader :month_start, :today, :time_zone, :dry_run, :sku_scope

    # The four full weeks before the Monday of the week `today` is in, the same window the actual-data queries use.
    def data_to
      today.beginning_of_week(:monday) - 1.day
    end

    def data_from
      data_to - (Ec::SkuProfitActualInputs::WEEKS * 7 - 1).days
    end

    def build_for(sku)
      version = sku.profit_versions.new(
        kind: "automatic", status: "published", name: month_start.strftime("%Y-%m"),
        effective_from: month_start, effective_to: month_start.end_of_month, data_from:, data_to:
      )
      version.system_write = true
      Ec::SkuProfitStandardContexts.build_missing(version, sku:, effective_on: month_start)

      builder = ScenarioBuilder.new(sku:, today:, time_zone:)
      scenarios = version.contexts.map { |context| builder.fill(context) }
      persist(sku, version) unless dry_run

      calculable = scenarios.count { |scenario| scenario.fetch(:status) == "valid" }
      {
        sku_code: sku.sku_code, scenarios: scenarios.size, calculable:,
        not_calculable: scenarios.reject { |scenario| scenario.fetch(:status) == "valid" }
      }
    end

    # Replaces the month's automatic version of the SKU, if there is one, with the one just built.
    def persist(sku, version)
      Ec::SkuProfitVersion.transaction do
        sku.profit_versions.automatic.where(effective_from: month_start).find_each do |existing|
          existing.system_write = true
          existing.destroy!
        end
        version.save!
      end
    end

    # Fills one scenario from the sources above and calculates it. Caches per instance: build one per SKU.
    class ScenarioBuilder
      LOGISTICS_FIGURES = Ec::SkuProfitVersionContext::LOGISTICS_FIGURE_COLUMNS

      def initialize(sku:, today:, time_zone:)
        @sku = sku
        @today = today
        @time_zone = time_zone
        @actuals = Ec::SkuProfitActualInputs.new(sku:, today:, time_zone:)
        @commission = {}
      end

      # => { scenario:, status: "valid" | "incomplete", errors: [codes], reasons: { source => reason } }
      def fill(context)
        identity = context.attributes.slice(*IDENTITY_KEYS)
        reasons = {}

        actual = @actuals.call(identity:, exchange_rate: context.exchange_rate_rub_cny || Ec::SkuProfitCalculator::DEFAULT_EXCHANGE_RATE_RUB_CNY)
        values = actual.fetch(:values)
        reasons["actual_data"] = actual.fetch(:unavailable) if actual.fetch(:unavailable).any?

        commission = commission_for(context)
        values["commission_rate"] = commission[:rate] if commission[:rate]
        reasons["commission_rate"] = commission[:reason] if commission[:reason]

        price = Ec::SkuProfitPriceFromActuals.realized_price_for(@sku, context, today: @today, time_zone: @time_zone)
        values["commission_base_price_rub"] = price[:price_rub] if price[:price_rub]
        reasons["price"] = price[:reason] if price[:reason]

        context.assign_input_values(values)
        result = calculate(context)
        context.apply_calculation_result(result)

        {
          scenario: Ec::SkuProfitStandardContexts.key_for(identity),
          status: context.calculation_status,
          errors: Array(result[:errors]),
          reasons: reasons
        }
      end

      private

      # Real freight figures when the scenario has outbound figures and they are not what stops the calculation: the
      # result with them is valid, or fails only for what the fixed formula lacks as well (a price, a commission
      # rate). Otherwise the fixed formula, with the figures cleared: the formula ignores them, and a version should
      # not hold figures it does not use.
      def calculate(context)
        if context.outbound_logistics_rub.present?
          context.logistics_mode = "actual"
          actual = Ec::SkuProfitCalculator.call_for_context(context)
          return actual if (Array(actual[:errors]) - formula_errors(context)).empty?
        end

        context.assign_input_values(LOGISTICS_FIGURES.index_with(nil))
        context.logistics_mode = "formula"
        Ec::SkuProfitCalculator.call_for_context(context)
      end

      def formula_errors(context)
        context.logistics_mode = "formula"
        Array(Ec::SkuProfitCalculator.call_for_context(context)[:errors])
      ensure
        context.logistics_mode = "actual"
      end

      def commission_for(context)
        @commission[[ context.platform, context.delivery_mode ]] ||=
          Ec::SkuOfficialCommissionRate.call(sku: @sku, platform: context.platform, delivery_mode: context.delivery_mode)
      end
    end
  end
end
