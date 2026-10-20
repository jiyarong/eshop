module Ec
  # Fills the commission base price of draft-version scenarios that have none from the price
  # actually realized in that scenario over the last four full weeks (see
  # SkuActualScenarioPriceQuery), then recalculates the version. Only drafts are touched, only
  # empty prices are filled, and a scenario with no orders of its own stays empty: a price is
  # never borrowed from another scenario.
  class SkuProfitPriceFromActuals
    IMPORT_NOTE_PREFIX = "sku-profit-pricing-sheet-import:".freeze
    DEFAULT_TIME_ZONE = "Asia/Shanghai".freeze
    # A realized price is only trusted when at least this many units were sold in the scenario.
    MIN_UNITS = 5

    # Decides the price of one scenario that has none. Returns
    #   { price_rub:, units:, orders: }                     when it can be filled (the caller assigns it)
    #   { reason: "no_orders_in_scenario" | "too_few_units" | "missing_exchange_rate" | "market_not_measurable", units: }
    # Shared by this service and the monthly refresh.
    def self.realized_price_for(sku, context, today:, time_zone:, min_units: MIN_UNITS)
      # WB orders carry no buyer country, so their orders cannot be told apart by market: the
      # price a Belarus scenario would get is the Russian one. Only the ledger knows the market.
      return { reason: "market_not_measurable", units: 0 } if context.platform == "wb" && context.market == "by"

      price = Ec::SkuActualScenarioPriceQuery.run(
        sku:, platform: context.platform, market: context.market, delivery_mode: context.delivery_mode,
        company_type: context.company_type.presence || "general", today:, time_zone:
      ).fetch(:commission_base_price)
      units = price[:unit_count].to_i
      average = price[:average_rub]
      return { price_rub: average, units:, orders: price[:item_count] } if average.present? && units >= min_units

      reason = if average.present? then "too_few_units"
      elsif price[:missing_exchange_rate_item_count].to_i.positive? then "missing_exchange_rate"
      else "no_orders_in_scenario"
      end
      { reason:, units: }
    end

    def self.run(**options)
      new(**options).call
    end

    # scope: the versions to look at (default: drafts created by the pricing sheet import).
    # min_units: the fewest sold units a price may be based on.
    def initialize(scope: nil, today: nil, time_zone: DEFAULT_TIME_ZONE, min_units: MIN_UNITS, dry_run: true)
      @time_zone = ActiveSupport::TimeZone[time_zone.to_s] || ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
      @today = (today || @time_zone.today).to_date
      @min_units = min_units
      @dry_run = dry_run
      @scope = scope || Ec::SkuProfitVersion.where(status: "draft").where("note LIKE ?", "#{IMPORT_NOTE_PREFIX}%")
    end

    def call
      summary = { mode: dry_run ? "dry_run" : "apply", min_units:, versions: 0, contexts_without_price: 0,
        filled: [], not_filled: [], failures: [] }
      scope.includes(:sku, :contexts).find_each do |version|
        summary[:versions] += 1
        fill_version(version, summary)
      rescue StandardError => error
        summary[:failures] << { version_id: version.id, error: "#{error.class}: #{error.message}" }
      end
      summary[:ok] = summary[:failures].empty?
      summary
    end

    private

    attr_reader :scope, :today, :time_zone, :min_units, :dry_run

    def fill_version(version, summary)
      changed = false
      version.contexts.each do |context|
        next if context.commission_base_price_rub.present?

        summary[:contexts_without_price] += 1
        entry = { sku_code: version.sku.sku_code, version_id: version.id, scenario: scenario_of(context) }
        result = self.class.realized_price_for(version.sku, context, today:, time_zone:, min_units:)

        if result[:price_rub]
          context.commission_base_price_rub = result[:price_rub]
          changed = true
          summary[:filled] << entry.merge(price_rub: result[:price_rub].to_f.round(2), units: result[:units], orders: result[:orders])
        else
          summary[:not_filled] << entry.merge(reason: result[:reason], units: result[:units])
        end
      end
      return unless changed

      Ec::SkuProfitVersionRecalculator.call(version)
      return if dry_run

      # The contexts are not autosaved with the version: save the changed ones explicitly.
      Ec::SkuProfitVersion.transaction do
        version.contexts.each { |context| context.save! if context.has_changes_to_save? }
      end
    end

    def scenario_of(context)
      context.attributes.slice("platform", "market", "delivery_mode", "company_type")
    end
  end
end
