module SalesFunnelReports
  # Estimated profit of each funnel period: units of the period placed into the SKU's pricing
  # scenarios x that scenario's per-unit profit from a profit version. Two bases:
  #   orders      every order item placed in the period, whatever its status
  #   conversions completed + returned order items
  # Both come from the order table, so the two bases are comparable and differ only by status.
  # The unit profit already carries the return-rate amortization, so this is an estimate, not
  # the settled profit: it answers "what is this volume worth at the version's parameters".
  class SkuProfitEstimateQuery
    BASES = %i[orders conversions].freeze

    def self.run(sku:, funnel_analysis:)
      new(sku:, funnel_analysis:).call
    end

    # The same estimate for units that were counted elsewhere (the SKU workbench list):
    # scenario_units = { orders: { scenario_key => units }, conversions: { ... } }.
    # with_options: also the estimate under every one of the SKU's versions (`options`, newest first, the same shape as
    # the result itself), for a page that lets the reader switch the version.
    def self.estimate_units(scenario_units:, versions:, to_date:, with_options: false)
      units = BASES.index_with do |basis|
        scenario_units.fetch(basis, {}).transform_values(&:to_d)
      end
      version = version_for(versions, to_date, units: units[:orders])
      result = {
        version: version && version_summary(version),
        bases: BASES.index_with { |basis| basis_estimate(units.fetch(basis), version) }
      }
      return result unless with_options

      result.merge(options: versions.map do |candidate|
        { version: version_summary(candidate), bases: BASES.index_with { |basis| basis_estimate(units.fetch(basis), candidate) } }
      end)
    end

    # The SKU's newest automatic version (the latest month of the automatic series), unless it cannot price the period:
    # given the period's units by scenario (`units`), an automatic version that prices none of them gives way to the
    # SKU's manual version, the current one (see Ec::SkuProfitVersion.resolve_for; its date only matters for SKUs that
    # have not marked one). Whichever version is chosen serves every basis of the period. When neither can price
    # the units, or only one kind exists, the first of them is kept.
    def self.version_for(versions, date, units: nil)
      automatic = versions.select(&:automatic?).max_by { |version| [ version.effective_from, version.id.to_i ] }
      manual = Ec::SkuProfitVersion.resolve_for(versions.reject(&:automatic?), date: date)
      candidates = [ automatic, manual ].compact
      return candidates.first if units.nil?

      candidates.find { |version| basis_estimate(units, version)[:profit_cny] } || candidates.first
    end

    def self.version_summary(version)
      { id: version.id, name: version.name, kind: version.kind, status: version.status, current: version.is_current?, effective_from: version.effective_from }
    end

    def self.basis_estimate(units_by_scenario, version)
      scenarios = units_by_scenario.filter_map do |key, units|
        next if units.zero?

        if key == :uncovered
          { identity: nil, units:, unit_profit_cny: nil, profit_cny: nil }
        else
          unit_profit = unit_profit_for(version, key)
          { identity: %w[platform market delivery_mode company_type].zip(key).to_h, units:,
            unit_profit_cny: unit_profit, profit_cny: unit_profit && units * unit_profit }
        end
      end
      scenarios.sort_by! { |entry| [ entry[:identity].nil? ? 1 : 0, -entry[:units] ] }
      priced = scenarios.select { |entry| entry[:profit_cny] }
      priced_units = priced.sum(0.to_d) { |entry| entry[:units] }
      profit = priced.empty? ? nil : priced.sum(0.to_d) { |entry| entry[:profit_cny] }

      {
        units: scenarios.sum(0.to_d) { |entry| entry[:units] },
        priced_units:,
        profit_cny: profit,
        # Profit per unit over the units that have a priced scenario (the profit covers no others).
        unit_average_cny: profit && priced_units.positive? ? profit / priced_units : nil,
        scenarios:
      }
    end

    def self.unit_profit_for(version, key)
      return unless version

      platform, market, delivery_mode, company_type = key
      context = version.contexts.find do |candidate|
        candidate.platform == platform && candidate.market == market && candidate.delivery_mode == delivery_mode &&
          candidate.warehouse_region.to_s == "main" && candidate.company_type.to_s == company_type
      end
      return unless context&.calculation_status == "valid"

      context.profit_cny&.to_d
    end

    def initialize(sku:, funnel_analysis:)
      @sku = sku
      @funnel_analysis = funnel_analysis
    end

    def call
      versions = sku.profit_versions.includes(:contexts).order(effective_from: :desc, id: :desc).to_a
      { periods: Array(funnel_analysis[:periods]).map { |period| estimate_period(period, versions) } }
    end

    private

    attr_reader :sku, :funnel_analysis

    def estimate_period(period, versions)
      units = BASES.index_with { Hash.new(0.to_d) }
      Array(funnel_analysis[:store_groups]).each do |group|
        row = group.dig(:rows_by_period, period.fetch(:key))
        next unless row

        scenario_units = row[:scenario_units] || {}
        BASES.each do |basis|
          scenario_units.fetch(basis, {}).each { |key, quantity| units[basis][key] += quantity.to_d }
        end
      end

      self.class.estimate_units(scenario_units: units, versions:, to_date: period.fetch(:to_date)).merge(
        key: period.fetch(:key), from_date: period.fetch(:from_date), to_date: period.fetch(:to_date)
      )
    end
  end
end
